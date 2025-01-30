import sys
from seabreeze import spectrometers as sb
from seabreeze.spectrometers import list_devices
import RPi.GPIO as GPIO
from RpiMotorLib import RpiMotorLib
import time
import csv 
import numpy as np
import os
import math
import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt
 # <-- Add this import
#desired x and y lengths in mm (CHANGE ACCORDINGLY)
desired_length = 420
desired_width= 280
desired_step_size = 20
integration_time = 1

#gpio configuration
direction2=17
direction1=22
step2=27
step1=24
en_pin1=0
en_pin2=0

#motor parameters
step_angle = 1.8 #degrees
motor_radius = 10 #mm
circumference = math.pi * 2 * motor_radius
steps_per_rev = 200
step_distance = circumference / steps_per_rev
x_steps = int (desired_length / desired_step_size)
y_steps = int (desired_width / desired_step_size)
x_step = int(desired_step_size / step_distance)
y_step = x_step
step_delay =.01



#initializing motors 
motor1= RpiMotorLib.A4988Nema(direction1, step1, (-1,-1,-1), "DRV8825")
motor2 = RpiMotorLib.A4988Nema(direction2, step2, (-1,-1,-1), "DRV8825")

#movement parameters
counter_clockwise = False
x_pos = 0
y_pos = 0


#ocean optics data setup
data= [["integrated intensity", "x", "y"]]
devices = sb.list_devices()
filename = "uniformity_test.csv"


def ocean_test(x,y):
    print (f"testing at point {x}, {y}")
    spec = sb.Spectrometer(devices[0])
    spec.integration_time_micros = integration_time*1000000
    wavelengths = spec.wavelengths()
    intensities = spec.intensities()
    integrated_intensity = np.trapezoid(intensities, wavelengths)
    local_data = [integrated_intensity, x, y ]
    print(local_data)
    data.append(local_data)

def load_position():
    global x_pos, y_pos
    if os.path.exists("position.txt"):
        try:
            with open("position.txt", "r") as file:
                line = file.readline()
                if line:
                    parts = line.split(",")
                    if len(parts) != 2:
                        print("Invalid format in position.txt.")
                        return 0, 0
                    try:
                        x_pos = int(parts[0])
                        y_pos = int(parts[1])
                    except ValueError:
                        print("Invalid values in position.txt. Returning to (0, 0).")
                        return 0, 0
                    print(f"Loaded position: x={x_pos}, y={y_pos}")
                    return x_pos, y_pos
        except Exception as e:
            print(f"Error reading position file: {e}. Returning to (0, 0).")
            return 0, 0
    else:
        # If the file doesn't exist, initialize position as (0, 0)
        save_position(0, 0)
        return 0, 0

def save_position(x, y):
    with open("position.txt", "w") as file:
        file.write(f"{x}, {y}")
    print(f"Saved position: x={x}, y={y}")

def return_to_origin():
    x_pos, y_pos = load_position()
    print(f"Returning to origin. Current position: x={x_pos}, y={y_pos}")

    while x_pos > 0:
        motor1.motor_go(False, "Full", x_step, step_delay, True, .05)
        x_pos -= desired_step_size
        print(f"Moving motor1: x_pos={x_pos}")
        save_position(x_pos, y_pos)  # Save position after each move

    while y_pos > 0:
        motor2.motor_go(False, "Full", y_step, step_delay, True, .05)
        y_pos -= desired_step_size
        print(f"Moving motor2: y_pos={y_pos}")
        save_position(x_pos, y_pos)  # Save position after each move

    print("Returned to origin and saved position (0, 0).")


def bleh(x_pos, y_pos):
        for y in range(0, y_steps):  # Loop over Y direction (Width)
            move_right = (y % 2 == 0)  # Move in a zigzag pattern for X movement
            for x in range(0, x_steps):  # Loop over X direction (Length)
                # Move motor1 along the x-axis (Length direction)
                motor1.motor_go(move_right, "Full", x_step, step_delay, True, .05)
                x_pos = x_pos + desired_step_size if move_right else x_pos - desired_step_size  # Update X position
                motor1.motor_stop()
                ocean_test(x_pos, y_pos)  # Test and save data at the current position
                sleep(integration_time)
                save_position(x_pos, y_pos)

        # Move motor2 along the y-axis (Width direction)
            motor2.motor_go(False, "Full", y_step, step_delay, True, .05)
            y_pos += desired_step_size  # Update Y position
            save_position(x_pos, y_pos)

        with open(filename, 'w', newline='') as csvfile:
            csvwriter =csv.writer(csvfile)
            csvwriter.writerows(data)
        
def go_to (x_goal,y_goal): #brings carriage to goal location
    x_pos, y_pos = load_position()
    print(f"Returning to origin. Current position: x={x_pos}, y={y_pos}")

    while x_pos > x_goal:
        motor1.motor_go(False, "Full", x_step, step_delay, True, .05)
        x_pos -= desired_step_size
        print(f"Moving motor1: x_pos={x_pos}")
        save_position(x_pos, y_pos)  # Save position after each move

    while y_pos > y_goal:
        motor2.motor_go(False, "Full", y_step, step_delay, True, .05)
        y_pos -= desired_step_size
        print(f"Moving motor2: y_pos={y_pos}")
        save_position(x_pos, y_pos)
        
    while x_pos < x_goal:
        motor1.motor_go(True, "Full", x_step, step_delay, True, .05)
        x_pos += desired_step_size
        print(f"Moving motor1: x_pos={x_pos}")
        save_position(x_pos, y_pos)  # Save position after each move

    while y_pos < y_goal:
        motor2.motor_go(True, "Full", y_step, step_delay, True, .05)
        y_pos += desired_step_size
        print(f"Moving motor2: y_pos={y_pos}")
        save_position(x_pos, y_pos)
                      
def graph():
    filename = 'uniformity_test.csv'
    df = pd.read_csv(filename)

    # Ensure 'x' and 'y' are integers, and check for any missing or invalid values
    df['x'] = pd.to_numeric(df['x'], errors='coerce').fillna(0).astype(int)
    df['y'] = pd.to_numeric(df['y'], errors='coerce').fillna(0).astype(int)
    df['integrated intensity'] = pd.to_numeric(df['integrated intensity'], errors='coerce').fillna(0)

    # Debugging print: check the unique values of 'x' and 'y'
    print(f"Unique x values: {df['x'].unique()}")
    print(f"Unique y values: {df['y'].unique()}")

    x_max = df['x'].max()
    y_max = df['y'].max()

    # Create an empty grid (initialized to NaN)
    grid = np.full((y_max + 1, x_max + 1), np.nan)

    # Fill the grid with intensity values at corresponding (x, y) positions
    for _, row in df.iterrows():
        x = int(row['x'])
        y = int(row['y'])
        intensity = row['integrated intensity']

        # Ensure that intensity is not NaN before assigning
        if 0 <= x <= x_max and 0 <= y <= y_max:
            grid[y, x] = intensity

    # Replace NaN values with 0 (or another small value) for plotting
    grid = np.nan_to_num(grid, nan=0)

    # Calculate the mean intensity of the grid
    mean_intensity = np.mean(grid)

    # Calculate the percent difference from the average for each value
    grid_percent_diff = np.abs(grid - mean_intensity) / mean_intensity * 100

    # Debugging: Check grid after populating and calculating percent differences
    print(f"Populated grid (percent differences):\n{grid_percent_diff}")

    # Normalize the percent difference values for better visualization
    min_diff = np.min(grid_percent_diff)
    max_diff = np.max(grid_percent_diff)

    grid_normalized = (grid_percent_diff - min_diff) / (max_diff - min_diff)

    # Debugging: Check normalized grid
    print(f"Normalized grid (percent differences):\n{grid_normalized}")

    # Plotting the heatmap
    plt.figure(figsize=(10, 8))  # Set the size of the plot
    sns.heatmap(grid_normalized, cmap="viridis", annot=False, cbar=True)

    # Add labels and a title
    plt.xlabel('X Position (mm)')
    plt.ylabel('Y Position (mm)')
    plt.title('Spectral Intensity Heatmap (Percent Difference from Average)')

    # Save the plot as a PNG image
    plt.savefig('heatmap.png')

    # Show the plot
    plt.show(block=True)
    print("done")
graph()