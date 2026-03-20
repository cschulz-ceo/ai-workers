#!/usr/bin/env python3
"""
CadQuery execution helper.
Usage: python execute_cq.py <code_file> <stl_output_path>
Exit code 0 = success, 1 = error (error printed to stderr)
"""
import sys
import os
import traceback

def main():
    if len(sys.argv) < 3:
        print("Usage: execute_cq.py <code_file> <stl_output>", file=sys.stderr)
        sys.exit(1)

    code_file = sys.argv[1]
    stl_output = sys.argv[2]

    try:
        with open(code_file, 'r') as f:
            code = f.read()
    except Exception as e:
        print(f"Failed to read code file: {e}", file=sys.stderr)
        sys.exit(1)

    # Create a clean execution namespace with cadquery pre-imported
    try:
        import cadquery as cq
    except ImportError as e:
        print(f"cadquery not installed: {e}", file=sys.stderr)
        sys.exit(1)

    namespace = {
        '__name__': '__main__',
        'cq': cq,
    }

    # Execute the user code
    try:
        exec(compile(code, code_file, 'exec'), namespace)
    except Exception as e:
        tb = traceback.format_exc()
        print(f"Code execution error:\n{tb}", file=sys.stderr)
        sys.exit(1)

    # Find the 'result' variable
    result = namespace.get('result')
    if result is None:
        # Try to find any Assembly or Workplane object
        for val in namespace.values():
            if hasattr(val, 'val') and hasattr(val, 'workplane'):
                result = val
                break
        if result is None:
            print("No 'result' variable found. Make sure your code assigns the final model to 'result'.", file=sys.stderr)
            sys.exit(1)

    # Export to STL
    try:
        from cadquery import exporters
        exporters.export(result, stl_output)
    except Exception as e:
        tb = traceback.format_exc()
        print(f"STL export error:\n{tb}", file=sys.stderr)
        sys.exit(1)

    if not os.path.exists(stl_output) or os.path.getsize(stl_output) == 0:
        print("STL export produced empty file", file=sys.stderr)
        sys.exit(1)

    print(f"OK: exported to {stl_output}")
    sys.exit(0)


if __name__ == '__main__':
    main()
