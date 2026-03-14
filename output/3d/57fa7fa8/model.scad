// Variable declarations
diameter = 8; // Outer diameter of the bolt cap
height = 3; // Height of the bolt cap
hex_diameter = 6; // Diameter of the hex recess
hex_height = 2; // Depth of the hex recess
tolerance = 0.1; // Tolerance for 3D printing

// Bolt cap with hex recess
difference() {
    // Main cylinder of the bolt cap
    cylinder(h = height, d = diameter + tolerance, $fn = 100);
    // Hex recess
    translate([0, 0, (height - hex_height) / 2])
        cylinder(h = hex_height, d = hex_diameter - tolerance, $fn = 6);
}

// Center the model at origin
translate([0, 0, -height / 2]) {}