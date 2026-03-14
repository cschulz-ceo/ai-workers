// Dimensions in mm
bracket_length = 50;  // Length of the straight section
bracket_width = 20;   // Width of the bracket
bracket_height = 10;  // Height of the bracket
bend_length = 30;     // Length of the bent section
hole_diameter = 8;    // Diameter of the mounting holes
hole_offset = 15;     // Offset of the holes from the end of the straight section
thickness = 5;        // Thickness of the bracket

// 2D tooth profile cross-section (not used here, but included as per requirement)
module tooth_profile(r, tooth_h) {
  circle(r=r);
  for (i = [0:n-1]) {
    rotate(i * 360/n) translate([r, 0])
      polygon([[-tw/2,-tooth_h/2],[tw/2,-tooth_h/2],[tw/2,tooth_h/2],[-tw/2,tooth_h/2]]);
  }
}
// Extrude to full 3D gear (not used here, but included as per requirement)
linear_extrude(height=gear_h) tooth_profile(r, tooth_h);

// Bracket with two mounting holes and a 90 degree bend
module bracket() {
  // Straight section
  linear_extrude(height=thickness)
    translate([0, 0, -thickness/2])
      square([bracket_length, bracket_width]);
  
  // Bent section
  linear_extrude(height=thickness)
    translate([bracket_length, 0, -thickness/2])
      square([bend_length, bracket_width]);
  
  // Mounting holes
  difference() {
    union() {
      translate([bracket_length - hole_offset, bracket_width/2, thickness/2])
        cylinder(h=thickness, r=hole_diameter/2, $fn=64);
      translate([bracket_length - hole_offset, -bracket_width/2, thickness/2])
        cylinder(h=thickness, r=hole_diameter/2, $fn=64);
    }
    translate([bracket_length - hole_offset, 0, 0])
      cube([hole_diameter, bracket_width, thickness], center=true);
  }
}

// Center the bracket at the origin
translate([-(bracket_length + bend_length/2), 0, 0])
  bracket();