import xml.etree.ElementTree as ET
import os

def create_item(parent, className, name):
    item = ET.SubElement(parent, "Item", {"class": className})
    properties = ET.SubElement(item, "Properties")
    name_prop = ET.SubElement(properties, "string", {"name": "Name"})
    name_prop.text = name
    return item, properties

def add_script_source(properties, source):
    source_prop = ET.SubElement(properties, "ProtectedString", {"name": "Source"})
    source_prop.text = source

def add_vector3(properties, name, x, y, z):
    vec = ET.SubElement(properties, "Vector3", {"name": name})
    ET.SubElement(vec, "X").text = str(x)
    ET.SubElement(vec, "Y").text = str(y)
    ET.SubElement(vec, "Z").text = str(z)

def add_bool(properties, name, val):
    b = ET.SubElement(properties, "bool", {"name": name})
    b.text = "true" if val else "false"

def main():
    root = ET.Element("roblox", {
        "xmlns:xmime": "http://www.w3.org/2005/05/xmlmime",
        "xmlns:xsi": "http://www.w3.org/2001/XMLSchema-instance",
        "xsi:noNamespaceSchemaLocation": "http://www.roblox.com/roblox.xsd",
        "version": "4"
    })

    # Workspace Setup
    workspace_item, ws_props = create_item(root, "Workspace", "Workspace")

    # Baseplate
    baseplate, bp_props = create_item(workspace_item, "Part", "Baseplate")
    add_vector3(bp_props, "Size", 512, 16, 512)
    add_vector3(bp_props, "Position", 0, -8, 0)
    add_bool(bp_props, "Anchored", True)

    # SpawnLocation
    spawn, spawn_props = create_item(workspace_item, "SpawnLocation", "SpawnLocation")
    add_vector3(spawn_props, "Size", 12, 1, 12)
    add_vector3(spawn_props, "Position", 0, 0.5, 0)
    add_bool(spawn_props, "Anchored", True)

    # ServerScriptService
    sss_item, sss_props = create_item(root, "ServerScriptService", "ServerScriptService")

    # Load and Inject AdvancedCombatEngine.lua
    script_path = os.path.join(os.path.dirname(__file__), "AdvancedCombatEngine.lua")
    if os.path.exists(script_path):
        with open(script_path, "r", encoding="utf-8") as f:
            source_code = f.read()
        
        script_item, script_props = create_item(sss_item, "Script", "AdvancedCombatEngine")
        add_script_source(script_props, source_code)
        print("Injected AdvancedCombatEngine.lua source into ServerScriptService.")
    else:
        print(f"Error: Could not find script at {script_path}")

    # Write out the .rbxlx XML place file
    output_path = os.path.join(os.path.dirname(__file__), "DemoPlace.rbxlx")
    tree = ET.ElementTree(root)
    tree.write(output_path, encoding="utf-8", xml_declaration=True)
    print(f"Successfully generated Roblox Place file at: {output_path}")

if __name__ == "__main__":
    main()
