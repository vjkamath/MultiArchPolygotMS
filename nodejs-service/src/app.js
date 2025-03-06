const express = require("express");
const app = express();
const port = process.env.PORT || 3000;

// Health check endpoint
app.get("/health", (req, res) => {
  res.status(200).send("OK");
});

// API endpoint
app.get("/info", (req, res) => {
  res.json({
    service: "nodejs",
    architecture: process.arch,
    platform: process.platform,
    timestamp: new Date().toISOString(),
  });
});

// Root endpoint with HTML
app.get("/", (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
        <title>Polyglot Architecture Demo</title>
        <style>
            body {
                font-family: Arial, sans-serif;
                margin: 0;
                padding: 20px;
                background-color: #f0f2f5;
            }
            .container {
                max-width: 800px;
                margin: 0 auto;
                background-color: white;
                padding: 20px;
                border-radius: 8px;
                box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            }
            h1 {
                color: #1a73e8;
                text-align: center;
            }
            .service-info {
                margin: 20px 0;
                padding: 15px;
                border: 1px solid #ddd;
                border-radius: 4px;
            }
            .architecture-badge {
                display: inline-block;
                padding: 5px 10px;
                border-radius: 15px;
                color: white;
                font-size: 14px;
                margin-left: 10px;
            }
            .arm64 {
                background-color: #34a853;
            }
            .x86_64 {
                background-color: #1a73e8;
            }
            button {
                background-color: #1a73e8;
                color: white;
                border: none;
                padding: 10px 20px;
                border-radius: 4px;
                cursor: pointer;
                margin: 5px;
            }
            button:hover {
                background-color: #1557b0;
            }
            pre {
                background-color: #f8f9fa;
                padding: 15px;
                border-radius: 4px;
                overflow-x: auto;
            }
            .service-header {
                display: flex;
                align-items: center;
            }
            .timestamp {
                color: #666;
                font-size: 0.9em;
                margin-top: 5px;
            }
            .error {
                color: #dc3545;
                padding: 10px;
                border-left: 4px solid #dc3545;
                background-color: #f8d7da;
                margin: 10px 0;
                border-radius: 4px;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>Polyglot Architecture Demo</h1>
            
            <div class="service-info">
                <div class="service-header">
                    <h2>Frontend Service</h2>
                    <span class="architecture-badge arm64">ARM64</span>
                </div>
                <div id="nodejsInfo"></div>
                <button onclick="fetchNodeInfo()">Refresh Node.js Info</button>
            </div>

            <div class="service-info">
                <div class="service-header">
                    <h2>Backend Service</h2>
                    <span class="architecture-badge x86_64">X86_64</span>
                </div>
                <div id="pythonInfo"></div>
                <button onclick="fetchPythonInfo()">Refresh Python Info</button>
            </div>
        </div>

        <script>
            function formatResponse(data) {
                var formattedJson = JSON.stringify(data, null, 2);
                var timestamp = new Date().toLocaleString();
                return '<pre>' + formattedJson + '</pre>' +
                       '<div class="timestamp">Last updated: ' + timestamp + '</div>';
            }

            function fetchNodeInfo() {
                fetch('/info')
                    .then(function(response) {
                        if (!response.ok) {
                            throw new Error('HTTP error! status: ' + response.status);
                        }
                        return response.json();
                    })
                    .then(function(data) {
                        document.getElementById('nodejsInfo').innerHTML = formatResponse(data);
                    })
                    .catch(function(error) {
                        console.error('Error:', error);
                        document.getElementById('nodejsInfo').innerHTML = 
                            '<div class="error">Error fetching Node.js service data: ' + error.message + '</div>';
                    });
            }

                        function fetchPythonInfo() {
                fetch('/api')
                    .then(function(response) {
                        if (!response.ok) {
                            throw new Error('HTTP error! status: ' + response.status);
                        }
                        return response.json();
                    })
                    .then(function(data) {
                        document.getElementById('pythonInfo').innerHTML = formatResponse(data);
                    })
                    .catch(function(error) {
                        console.error('Error:', error);
                        document.getElementById('pythonInfo').innerHTML = 
                            '<div class="error">Error fetching Python service data: ' + error.message + '</div>';
                    });
            }


            // Initial load
            fetchNodeInfo();
            fetchPythonInfo();

            // Refresh every 30 seconds
            setInterval(function() {
                fetchNodeInfo();
                fetchPythonInfo();
            }, 30000);
        </script>
    </body>
    </html>
    `);
});

app.listen(port, "0.0.0.0", () => {
  console.log(`Node.js service listening at port ${port}`);
});
