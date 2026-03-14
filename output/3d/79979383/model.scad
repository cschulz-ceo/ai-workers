// Dimensions
cube_size = 20; // Size of the cube
hole_diameter = 10; // Diameter of the hole
hole_depth = 5; // Depth of the hole

// Cube with a hole in the top
translate([-cube_size/2, -cube_size/2, -cube_size/2]) {
    union() {
        // Cube
        cube(size = cube_size, center = false);
        // Hole in the top
        translate([cube_size/2, cube_size/2, cube_size - hole_depth/2])
            cylinder(h = hole_depth, d = hole_diameter, center = true);
    }
    // Subtract the hole from the cube
    difference() {
        cube(size = cube_size, center = false);
        translate([cube_size/2, cube_size/2, cube_size - hole_depth/2])
            cylinder(h = hole_depth, d = hole_diameter, center = true);
    }
}