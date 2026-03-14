// Variable declarations for dimensions and tolerances
wall_thickness = 3; // Thickness of the wall
tray_width = 100; // Width of the tray
tray_height = 20; // Height of the tray
tray_depth = 150; // Depth of the tray
divider_width = 15; // Width of each divider
divider_height = 10; // Height of each divider
divider_spacing = 20; // Spacing between dividers
snap_in_height = 5; // Height of the snap-in feature
tolerance = 0.2; // Tolerance for fit

// Main tray structure
tray_body = cube(size = [tray_width, tray_depth, tray_height], center = true);

// Cut out for snap-in feature on the bottom of the tray
snap_in_cutout = translate([0, 0, -snap_in_height/2])
                 cube(size = [tray_width - 2*wall_thickness, tray_depth - 2*wall_thickness, snap_in_height], center = true);

// Wall sections of the tray
wall_left = translate([-tray_width/2 + wall_thickness/2, 0, tray_height/2 - wall_thickness/2])
            cube(size = [wall_thickness, tray_depth, wall_thickness], center = true);

wall_right = translate([tray_width/2 - wall_thickness/2, 0, tray_height/2 - wall_thickness/2])
             cube(size = [wall_thickness, tray_depth, wall_thickness], center = true);

wall_back = translate([0, -tray_depth/2 + wall_thickness/2, tray_height/2 - wall_thickness/2])
            cube(size = [tray_width, wall_thickness, wall_thickness], center = true);

// Dividers with snap-in feature
divider = union() {
    // Main body of the divider
    cube(size = [divider_width, tray_depth - 2*wall_thickness, divider_height], center = true),
    // Snap-in feature on the top of the divider
    translate([0, 0, divider_height + snap_in_height/2])
    cube(size = [divider_width - 2*wall_thickness, tray_depth - 2*wall_thickness, snap_in_height], center = true)
};

// Positioning dividers along the depth of the tray
dividers = union() {
    for (i = [1 : (tray_depth - 2*wall_thickness - divider_width) / (divider_spacing + divider_width)])
        translate([0, -tray_depth/2 + wall_thickness + (divider_spacing + divider_width) * i - divider_spacing/2, divider_height/2])
        divider;
};

// Final assembly of the tray with dividers
translate([0, 0, tray_height/2])
difference() {
    union() {
        tray_body,
        wall_left,
        wall_right,
        wall_back
    },
    snap_in_cutout,
    dividers
}