import { Server } from "./packages/opencode/src/server/server"
import { writeFileSync, readFileSync, existsSync } from 'node:fs'
import { join, resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

async function generateOpenApi() {
  try {
    // robustly resolve paths relative to this script
    const rootDir = resolve(dirname(fileURLToPath(import.meta.url))); 
    const rootOpenapiPath = join(rootDir, 'openapi.json');
    const sdkPath = join(rootDir, 'packages/sdk/openapi.json');
    const docsPath = join(rootDir, 'packages/docs/openapi.json');

    console.log("Generating OpenAPI documentation...")
    const openapi = await Server.openapi()
    console.log("OpenAPI spec generated successfully")
    console.log("Total paths:", Object.keys(openapi.paths || {}).length)
    console.log("Title:", openapi.info?.title)
    console.log("Version:", openapi.info?.version)
    
    const openapiJson = JSON.stringify(openapi, null, 2);

    // 1. Write to root (optional but good for reference)
    writeFileSync(rootOpenapiPath, openapiJson)
    console.log(`\nOpenAPI spec written to ${rootOpenapiPath}`)

    // 2. Write to SDK explicitly (source of truth)
    writeFileSync(sdkPath, openapiJson)
    console.log(`OpenAPI spec written to ${sdkPath}`)

    // 3. Write to Docs (robustness: updates file or follows symlink)
    writeFileSync(docsPath, openapiJson)
    console.log(`OpenAPI spec written to ${docsPath}`)

    // Generate self-contained HTML dashboards
    console.log("Generating self-contained HTML dashboards...");
    const templatePath = join(rootDir, 'dashboard_template.html');
    
    if (!existsSync(templatePath)) {
        console.warn("dashboard_template.html not found, skipping HTML generation.");
        return openapi;
    }
    
    const template = readFileSync(templatePath, 'utf8');

    const categories = {
        mcp: ['/mcp', '/experimental/tool'],
        serve: ['/pty', '/tui'],
    };

    // Create copies of the spec for each category
    // Using JSON parse/stringify for deep copy to avoid reference issues, 
    // though shallow copy of root + new paths object is usually enough.
    const createSpec = (title: string) => ({
        ...openapi,
        info: { ...openapi.info, title },
        paths: {} as Record<string, any>
    });

    const specs = {
        web: createSpec("OpenCode Web API"),
        mcp: createSpec("OpenCode MCP API"),
        serve: createSpec("OpenCode Serve API")
    };

    Object.entries(openapi.paths || {}).forEach(([pathKey, pathItem]) => {
        if (categories.mcp.some(prefix => pathKey.startsWith(prefix))) {
            specs.mcp.paths[pathKey] = pathItem;
        } else if (categories.serve.some(prefix => pathKey.startsWith(prefix))) {
            specs.serve.paths[pathKey] = pathItem;
        } else {
            specs.web.paths[pathKey] = pathItem;
        }
    });

    const generateHtml = (filename: string, specData: any, title: string, indexLink: string) => {
        const jsonString = JSON.stringify(specData);
        let htmlContent = template.replace('/* __INJECT_JSON_HERE__ */ null', () => jsonString);
        // Replace title if placeholder exists
        htmlContent = htmlContent.replace('/* __INJECT_TITLE_HERE__ */ OpenCode API Dashboard', title);
        // Replace index link
        htmlContent = htmlContent.replace('/* __INJECT_INDEX_LINK_HERE__ */', indexLink);
        
        const outputPath = join(rootDir, filename);
        writeFileSync(outputPath, htmlContent);
        console.log(`Generated ${outputPath} (${Object.keys(specData.paths).length} paths)`);
    };

    generateHtml('OPENAPI_WEB.html', specs.web, "OpenCode Web API", "OPENAPI_WEB_INDEX.html");
    generateHtml('OPENAPI_MCP.html', specs.mcp, "OpenCode MCP API", "OPENAPI_WEB_INDEX.html");
    generateHtml('OPENAPI_SERVE.html', specs.serve, "OpenCode Serve API", "OPENAPI_SERVE_INDEX.html");

    // Generate Index Pages from templates
    console.log("Generating index pages...");
    const webIndexTemplate = join(rootDir, 'template_web_index.html');
    const serveIndexTemplate = join(rootDir, 'template_serve_index.html');

    if (existsSync(webIndexTemplate)) {
        writeFileSync(join(rootDir, 'OPENAPI_WEB_INDEX.html'), readFileSync(webIndexTemplate));
        console.log("Generated OPENAPI_WEB_INDEX.html");
    } else {
        console.warn("template_web_index.html not found");
    }

    if (existsSync(serveIndexTemplate)) {
        writeFileSync(join(rootDir, 'OPENAPI_SERVE_INDEX.html'), readFileSync(serveIndexTemplate));
        console.log("Generated OPENAPI_SERVE_INDEX.html");
    } else {
        console.warn("template_serve_index.html not found");
    }

    return openapi
  } catch (error) {
    console.error("Error generating OpenAPI spec:", error)
    throw error
  }
}

generateOpenApi().catch(console.error)