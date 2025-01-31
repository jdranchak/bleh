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
from time import sleep
import ast
 # <-- Add this import
#desired x and y lengths in mm (CHANGE ACCORDINGLY)
desired_length = 420
desired_width= 280
desired_step_size = 20
integration_time = .5

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
row_data =[]
devices = sb.list_devices()
filename = "uniformity_test.csv"


def ocean_test(x,y):
    print (f"testing at point {x}, {y}")
    spec = sb.Spectrometer(devices[0])
    spec.integration_time_micros = integration_time*1000000
    wavelengths = spec.wavelengths()
    intensities = spec.intensities()
    integrated_intensity = np.trapezoid(intensities, wavelengths)
    local_data = [integrated_intensity, x, y]
    return local_data

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
        global row_data, data
        for y in range(0, y_steps):  # Loop over Y direction (Width)
            move_right = (y % 2 == 0)  # Move in a zigzag pattern for X movement
            for x in range(0, x_steps):  # Loop over X direction (Length)
                # Move motor1 along the x-axis (Length direction)
                motor1.motor_go(move_right, "Full", x_step, step_delay, True, .05)
                x_pos = x_pos + desired_step_size if move_right else x_pos - desired_step_size  # Update X position
                motor1.motor_stop()
                local_data = ocean_test(x_pos, y_pos)  # Test and save data at the current position
                sleep(integration_time)
                save_position(x_pos, y_pos)
                row_data.append(local_data)

        # Move motor2 along the y-axis (Width direction)
            if not move_right:
                row_data.reverse()
            data.append(row_data)
            row_data=[]
            motor2.motor_go(False, "Full", y_step, step_delay, True, .05)
            y_pos += desired_step_size  # Update Y position
            save_position(x_pos, y_pos)
        
        print(data)

        with open(filename, 'w', newline='') as csvfile:
            csvwriter =csv.writer(csvfile)
            csvwriter.writerows(data)
            
        export_snake_grid()
        
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
                      

def export_snake_grid():
    filename = "uniformity_test.csv"
    df = pd.read_csv(filename)
    
    # Print the dataframe to see how it is structured
    print("CSV Data:")
    print(df)
    fields = []
    rows = []
    parsed_data = []
    row_data = []
    # reading csv file
    with open(filename, 'r') as csvfile:
        # creating a csv reader object
        csvreader = csv.reader(csvfile)

        # extracting field names through first row
        fields = next(csvreader)

        # extracting each data row one by one
        for row in csvreader:
            rows.append(row)

    for row1 in rows:
        for item in row1:
            row_data.append(float(item[item.find("(") + 1:item.find(")")]))
            
        print(row_data)
        parsed_data.append(row_data)
        row_data = []
            
        
    print(parsed_data)
    hm = sns.heatmap(data = parsed_data) 
  
# displaying the plotted heatmap 
    plt.show()
    # Call the function to export and generate the heatmap
bleh(0,0)
