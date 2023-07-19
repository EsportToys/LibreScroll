# LibreScroll
Smooth inertial scrolling with any regular mouse.


https://github.com/EsportToys/LibreScroll/assets/98432183/8bbec057-65aa-4d37-b726-42913cafded1

## Instructions
1. Run LibreScroll
2. Hold Mouse 3 and move your mouse, the cursor will stay in-place and mouse motion is converted to scroll momentum instead.
3. Release middle-mouse-button to halt scroll momentum and release the cursor.

## Options

![image](https://github.com/EsportToys/LibreScroll/assets/98432183/4980aadb-e5d4-4a52-a23f-27506e6cf934)

### Friction
The rate at which momentum decays.

### X/Y-Sensitivity
The horizontal/vertical sensitivity at which mouse movement is converted to scroll momentum. Set a negative sensitivity to use reversed-direction scrolling, or zero to disable that axis entirely

### Minimum X/Y Step
The granularity at which to send scrolling inputs. This is a workaround for some legacy apps that do not handle smooth scrolling increments correctly. A "standard" coarse scrollwheel step is 120.

### Flick Mode
When enabled, releasing middle-mouse-button will not halt the scrolling momentum. Press any button again (or move the actual wheel) to reset it.
