#!/usr/bin/env python3

# SVG Logo generator for this project
# https://hackaday.io/project/11864-tritiled

import math
import svgwrite
import os

dwg = svgwrite.Drawing('tritiled-logo.svg', size=(200,200))

#dwg.add(dwg.circle(center=(100,100), r=50, fill='#111111'))

r1 = 95
r3 = 80
r4 = 45
r5 = 35

cx=100
cy=100
ang = 60

dwg.add(dwg.circle(center=(cx, cy), r=r1, fill='none',
                   stroke='#000000', stroke_width=5))

for i in range(3):
    ang1 = 270*math.pi/180 -ang/2*math.pi/180 + 120*i*math.pi/180
    ang2 = 270*math.pi/180 +ang/2*math.pi/180 + 120*i*math.pi/180

    path = dwg.path(d=('M', cx+r3*math.cos(ang1), cy+r3*math.sin(ang1)),
                    fill='#000000', stroke='none')
    path.push('L', cx+r4*math.cos(ang1), cy+r4*math.sin(ang1))
    path.push('A', r4, r4, 0, 0, 1, cx+r4*math.cos(ang2), cy+r4*math.sin(ang2))
    path.push('L', cx+r3*math.cos(ang2), cy+r3*math.sin(ang2))
    path.push('A', r3, r3, 0, 0, 0, cx+r3*math.cos(ang1), cy+r3*math.sin(ang1))

    dwg.add(path)


cy -= 9   
a1 = -30*math.pi/180
a2 = -30*math.pi/180 - 120*math.pi/180
a3 = -30*math.pi/180 - 120*math.pi/180 - 120*math.pi/180
path = dwg.path(d=('M', cx+r5*math.cos(a1), cy+r5*math.sin(a1)),
                fill='#000000', stroke='none') 
path.push('L', cx+r5*math.cos(a2), cy+r5*math.sin(a2))
path.push('L', cx+r5*math.cos(a3), cy+r5*math.sin(a3))
path.push('L', cx+r5*math.cos(a1), cy+r5*math.sin(a1))
dwg.add(path)

dy = 41
th = 12
path = dwg.path(d=('M', cx+r5*math.cos(a1), dy+cy+r5*math.sin(a1)),
                fill='#000000', stroke='none') 
path.push('L', cx+r5*math.cos(a2), dy+cy+r5*math.sin(a2))
path.push('L', cx+r5*math.cos(a2), th+dy+cy+r5*math.sin(a2))
path.push('L', cx+r5*math.cos(a1), th+dy+cy+r5*math.sin(a1))
path.push('L', cx+r5*math.cos(a1), dy+cy+r5*math.sin(a1))
dwg.add(path)

dwg.save()

print(os.getcwd())