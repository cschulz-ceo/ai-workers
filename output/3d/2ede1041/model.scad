// Dimensions in mm
leaf_width = 50;    // Width of the hinge leaf
leaf_height = 100;  // Height of the hinge leaf
leaf_thickness = 5; // Thickness of the hinge leaf
pin_diameter = 5;   // Diameter of the hinge pin
pin_length = 60;    // Length of the hinge pin
gap = 2;            // Gap between the two leaves

// 2D tooth profile cross-section (not used for this model, but included as per requirement)
module tooth_profile(r, tooth_h) {
  circle(r=r);
  for (i = [0:n-1]) {
    rotate(i * 360/n) translate([r, 0])
      polygon([[-tw/2,-tooth_h/2],[tw/2,-tooth_h/2],[tw/2,tooth_h/2],[-tw/2,tooth_h/2]]);
  }
}
// Extrude to full 3D gear (not used for this model, but included as per requirement)
linear_extrude(height=gear_h) tooth_profile(r, tooth_h);

// Hinge leaf module
module hinge_leaf() {
  difference() {
    cube([leaf_width, leaf_height, leaf_thickness], center=true);
    translate([0, 0, -leaf_thickness/2 - 1]) // Cutout for the pin
      cylinder(h=leaf_thickness + 2, r=pin_diameter/2, center=true, $fn=64);
  }
}

// Main assembly
difference() {
  union() {
    hinge_leaf(); // First leaf
    translate([0, gap, 0]) hinge_leaf(); // Second leaf
  }
  // Hinge pin
  translate([0, gap/2, 0])
    cylinder(h=pin_length, r=pin_diameter/2, center=true, $fn=64);
}