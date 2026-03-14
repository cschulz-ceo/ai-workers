// Variable declarations
num_teeth = 8;          // Number of teeth
module_radius = 20;     // Radius of the gear module
pressure_angle = 20;    // Pressure angle in degrees
clearance = 0.05;       // Clearance between teeth
tolerance = 0.1;        // Tolerance for 3D printing

// Calculate derived dimensions
base_radius = module_radius * cos(radians(pressure_angle));
outer_radius = module_radius * (1 + 1.25 / tan(radians(pressure_angle)));
inner_radius = module_radius * (1 - 1.25 / tan(radians(pressure_angle)));
tooth_angle = 360 / num_teeth;
addendum = outer_radius - module_radius;
dedendum = module_radius - inner_radius;

// Gear module
module gear(num_teeth, module_radius, pressure_angle, clearance, tolerance) {
    // Base circle
    cylinder(h=tolerance, r=base_radius, $fn=num_teeth*2);

    // Teeth
    for (i = [0:num_teeth-1]) {
        rotate(i * tooth_angle) {
            translate([module_radius, 0, 0]) {
                difference() {
                    // Tooth profile
                    hull() {
                        cylinder(h=tolerance, r1=module_radius, r2=outer_radius, $fn=4);
                        translate([addendum, 0, 0]) cylinder(h=tolerance, r=outer_radius, $fn=4);
                    }
                    // Clearances
                    translate([addendum - clearance, 0, 0]) cylinder(h=tolerance, r=outer_radius, $fn=4);
                }
            }
        }
    }

    // Root circle
    cylinder(h=tolerance, r=inner_radius, $fn=num_teeth*2);
}

// Center the gear at the origin
translate([0, 0, tolerance/2]) gear(num_teeth, module_radius, pressure_angle, clearance, tolerance);