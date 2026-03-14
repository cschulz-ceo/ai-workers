// Dimensions in mm
n = 12; // Number of teeth
r = 15; // Outer radius of the gear
tooth_h = 3; // Height of the teeth
gear_h = 5; // Height of the gear
tw = 2; // Width of the teeth
bore_r = 2.5; // Radius of the center bore
bore_h = 5; // Height of the center bore

// 2D tooth profile cross-section
module tooth_profile(r, tooth_h) {
  circle(r=r);
  for (i = [0:n-1]) {
    rotate(i * 360/n) translate([r, 0])
      polygon([[-tw/2,-tooth_h/2],[tw/2,-tooth_h/2],[tw/2,tooth_h/2],[-tw/2,tooth_h/2]]);
  }
}

// Extrude to full 3D gear
linear_extrude(height=gear_h) tooth_profile(r, tooth_h);

// Center the gear and add the bore
translate([0, 0, -bore_h/2]) {
  difference() {
    // Gear body
    linear_extrude(height=gear_h) tooth_profile(r, tooth_h);
    // Center bore
    cylinder(r=bore_r, h=bore_h, $fn=64);
  }
}