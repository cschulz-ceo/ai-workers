// Variable declarations
cable_diameter = 20; // Diameter of the cable
clip_width = 30; // Width of the clip
clip_height = 15; // Height of the clip
clip_thickness = 5; // Thickness of the clip
clip_inner_gap = 2; // Gap inside the clip for cable clearance
clip_outer_radius = 5; // Radius of the outer rounded corners
clip_inner_radius = 2; // Radius of the inner rounded corners
tolerance = 0.2; // Tolerance for 3D printing

// Main clip body
union() {
    // Base of the clip
    difference() {
        cube([clip_width, clip_height, clip_thickness], center=true);
        translate([0, 0, -clip_thickness/2 - tolerance])
            cylinder(r=clip_outer_radius, h=clip_thickness + 2*tolerance, center=true);
    }
    // Inner gap for cable clearance
    translate([0, 0, clip_thickness/2])
        cylinder(r=(cable_diameter/2) + clip_inner_gap, h=clip_height, center=true);
}

// Rounded corners on the top
union() {
    for (i = [0:1]) {
        for (j = [0:1]) {
            translate([(-1 + 2*i)*(clip_width/2 - clip_outer_radius), (-1 + 2*j)*(clip_height/2 - clip_outer_radius), clip_thickness/2])
                cylinder(r=clip_outer_radius, h=clip_thickness, center=true);
        }
    }
}

// Rounded corners on the inner gap
union() {
    for (i = [0:1]) {
        translate([(-1 + 2*i)*(cable_diameter/2 + clip_inner_gap), 0, clip_thickness/2])
            cylinder(r=clip_inner_radius, h=clip_height, center=true);
    }
}

// Center the model at origin
translate([0, 0, -clip_thickness/2]) {}