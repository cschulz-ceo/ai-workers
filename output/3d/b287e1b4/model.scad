// Bolt dimensions in mm
thread_diameter = 8; // M8 thread diameter
head_diameter = 16; // Hex head diameter
head_height = 10; // Hex head height
bolt_length = 50; // Total bolt length
thread_length = 30; // Length of threaded section
thread_pitch = 1.25; // M8 thread pitch
thread_h = 1.5; // Thread height
$fn=64; // Smoothness of circles/cylinders

// 2D tooth profile cross-section for thread
module tooth_profile(r, tooth_h) {
  circle(r=r);
  for (i = [0:5]) {
    rotate(i * 60) translate([r, 0])
      polygon([[-thread_diameter/8,-tooth_h/2],[thread_diameter/8,-tooth_h/2],[thread_diameter/8,tooth_h/2],[-thread_diameter/8,tooth_h/2]]);
  }
}

// Extrude to full 3D thread
module thread_section(d, h, pitch, tooth_h) {
  rotate_extrude() tooth_profile(d/2, tooth_h);
  translate([0, 0, h]) cylinder(r=d/2, h=pitch, $fn=64);
}

// Bolt head
module hex_head(d, h) {
  linear_extrude(height=h) hexagon(d);
}

// Hexagon profile
module hexagon(size) {
  for (i = [0:5]) {
    rotate(i * 60) translate([size/2, 0]) square([size/2, size * sqrt(3)/2], center=true);
  }
}

// Main bolt assembly
difference() {
  // Full bolt cylinder
  cylinder(r=head_diameter/2, h=bolt_length, $fn=64);
  
  // Threaded section
  translate([0, 0, head_height]) thread_section(thread_diameter, thread_length, thread_pitch, thread_h);
  
  // Hex head
  hex_head(head_diameter, head_height);
  
  // Center the bolt at the origin
  translate([0, 0, -bolt_length/2]);
}