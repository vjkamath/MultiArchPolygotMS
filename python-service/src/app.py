from flask import Flask, jsonify
import platform
from datetime import datetime
import os
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

port = int(os.environ.get('PORT', 5000))

@app.route('/health')
def health():
    return 'OK'

@app.route('/')
def root():
    return api()

@app.route('/api')
def api():
    return jsonify({
        'service': 'python',
        'architecture': platform.machine(),
        'platform': platform.system(),
        'timestamp': datetime.utcnow().isoformat()
    })

if __name__ == '__main__':
    print(f"Starting Python service on port {port}")
    app.run(host='0.0.0.0', port=port)
