// Variable declarations
cube_size = 20; // Size of the cube
hole_diameter = 10; // Diameter of the hole
hole_depth = 5; // Depth of the hole

// Main model
translate([-cube_size/2, -cube_size/2, -cube_size/2]) // Center the model at origin
union() {
    // Cube
    cube(size = cube_size, center = false);
    
    // Hole in the top
    translate([cube_size/2, cube_size/2, cube_size - hole_depth/2])
    difference() {
        cylinder(h = hole_depth, d = hole_diameter, center = true);
        cylinder(h = hole_depth + 0.1, d = hole_diameter - 0.1, center = true); // To ensure the hole is open at the top
    }
}