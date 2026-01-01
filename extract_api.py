import json

def generate_extracted_api():
    try:
        print("Loading full OpenAPI spec...")
        with open('openapi.json', 'r') as f:
            full_spec = json.load(f)
        
        print(f"Loaded spec with {len(full_spec.get('paths', {}))} paths")

        # Define the target paths for the "web UI" subset
        # Using a broad filter but ensuring we capture the ones mentioned in review
        target_keywords = ['session', 'file', 'config', 'provider', 'command', 'health', 'agent', 'vcs', 'project', 'tui', 'auth', 'mcp', 'global']
        
        filtered_paths = {}
        referenced_schemas = set()

        def collect_refs(obj):
            """Recursively find $ref values in a dict/list."""
            if isinstance(obj, dict):
                for k, v in obj.items():
                    if k == '$ref':
                        # refs look like "#/components/schemas/Session"
                        if v.startswith('#/components/schemas/'):
                            referenced_schemas.add(v.split('/')[-1])
                        # Note: We currently only handle schema refs. 
                        # Refs to parameters/responses/etc are ignored as they haven't been seen in source.
                    else:
                        collect_refs(v)
            elif isinstance(obj, list):
                for item in obj:
                    collect_refs(item)

        print("Filtering paths...")
        for path, methods in full_spec.get('paths', {}).items():
            # Check if path is relevant
            if any(k in path.lower() for k in target_keywords):
                filtered_paths[path] = methods
                collect_refs(methods)

        # Iteratively collect schemas because schemas can reference other schemas
        print("Collecting referenced schemas...")
        all_components = full_spec.get('components', {}).get('schemas', {})
        filtered_schemas = {}
        
        processed_schemas = set()
        queue = list(referenced_schemas)
        
        while queue:
            schema_name = queue.pop(0)
            if schema_name in processed_schemas:
                continue
                
            processed_schemas.add(schema_name)
            
            if schema_name in all_components:
                schema_body = all_components[schema_name]
                filtered_schemas[schema_name] = schema_body
                
                def collect_refs_schema(obj):
                    if isinstance(obj, dict):
                        for k, v in obj.items():
                            if k == '$ref' and v.startswith('#/components/schemas/'):
                                ref_name = v.split('/')[-1]
                                if ref_name not in processed_schemas:
                                    queue.append(ref_name)
                            else:
                                collect_refs_schema(v)
                    elif isinstance(obj, list):
                        for item in obj:
                            collect_refs_schema(item)
                            
                collect_refs_schema(schema_body)

        extracted_spec = {
            "openapi": full_spec.get("openapi", "3.1.1"),
            "info": full_spec.get("info", {}),
            "paths": filtered_paths,
            "components": {
                "schemas": filtered_schemas
            }
        }

        print(f"Extracted {len(filtered_paths)} paths and {len(filtered_schemas)} schemas")
        
        with open('extracted-api.json', 'w') as f:
            json.dump(extracted_spec, f, indent=2)
            
        print("Successfully wrote extracted-api.json")

    except Exception as e:
        print(f"Error: {e}")
        exit(1)

if __name__ == "__main__":
    generate_extracted_api()