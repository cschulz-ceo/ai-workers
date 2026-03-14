// Dimensions in mm
bolt_diameter = 6; // M6 bolt diameter
bolt_length = 30; // Length of the bolt
thread_pitch = 1; // Pitch of M6 thread
thread_height = 1.5; // Height of thread
head_diameter = 10; // Diameter of the bolt head
head_height = 5; // Height of the bolt head
$fn=64; // Quality of circles and cylinders

// Bolt head
module bolt_head(d, h) {
  cylinder(d=d, h=h, $fn=6); // Hexagonal head
}

// Bolt shank with threads
module bolt_shank(d, h, pitch, thread_h) {
  // 2D tooth profile cross-section for threads
  module tooth_profile(r, tooth_h) {
    circle(r=r);
    for (i = [0:5]) {
      rotate(i * 60) translate([r, 0])
        polygon([[-thread_h/2,-thread_h/2],[thread_h/2,-thread_h/2],[thread_h/2,thread_h/2],[-thread_h/2,thread_h/2]]);
    }
  }
  // Extrude to full 3D threads
  linear_extrude(height=h) tooth_profile(d/2, thread_h);
}

// Main bolt assembly
difference() {
  union() {
    bolt_head(head_diameter, head_height);
    translate([0, 0, head_height]) bolt_shank(bolt_diameter, bolt_length - head_height, thread_pitch, thread_height);
  }
  // Central hole for the screwdriver
  translate([0, 0, head_height/2]) cylinder(d=bolt_diameter - 1, h=head_height, $fn=6);
}