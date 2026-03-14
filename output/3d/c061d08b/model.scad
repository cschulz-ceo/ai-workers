// Dimensions
shelf_width = 100;       // Width of the shelf
shelf_thickness = 10;    // Thickness of the shelf
bracket_height = 30;     // Height of the bracket
bracket_thickness = 5;   // Thickness of the bracket
hole_diameter = 8;       // Diameter of the mounting holes
hole_distance = 50;      // Distance between the centers of the mounting holes
tolerance = 0.2;         // Tolerance for 3D printing

// Bracket
difference() {
    // Main bracket shape
    cube([shelf_width, bracket_thickness, bracket_height], center=true);
    
    // Cut out mounting holes
    translate([hole_distance/2, 0, bracket_height/2])
        cylinder(h=bracket_height + tolerance, d=hole_diameter + tolerance, center=true);
    translate([-hole_distance/2, 0, bracket_height/2])
        cylinder(h=bracket_height + tolerance, d=hole_diameter + tolerance, center=true);
}

// Translate to center the model at origin
translate([0, -shelf_thickness/2, 0])
    cube([shelf_width, shelf_thickness, bracket_height], center=true);