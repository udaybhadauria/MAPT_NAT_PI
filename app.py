from flask import Flask, request, jsonify, render_template
import json
import os
from mqtt_controller import push_config, start_mqtt

app = Flask(__name__, static_folder="templates")

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(BASE_DIR, "config_ui.json")

FIXED_PSID_LEN = 6
FIXED_V6_PREFIX = "2600:8809:a505:91d0::/60"

# -----------------------------
@app.route("/", methods=["GET"])
def index():
    dummy_config = {
        "dhcp6": {
            "subnet": "2600:8809:a505:91d0::/64",
            "dns": ["2001:4860:4860::8888", "2001:4860:4860::8844"],
            "pool": {
                "start": "2600:8809:a505:91d0::100",
                "end": "2600:8809:a505:91d0::1fff"
            }
        },
        "s46": {
            "v4_prefix": "192.168.0.0",
            "v4_plen": 24,
            "ea_len": 8,
            "v6_rule_prefix": "64:ff9b::",
            "dmr": "64:ff9b::1"
        }
    }
    return render_template("index.html", config=dummy_config)

# -----------------------------
@app.route("/apply", methods=["POST"])
def apply_config():
    macs = request.form.getlist("mac[]")
    psids = request.form.getlist("psid[]")

    devices = []
    for mac, psid in zip(macs, psids):
        devices.append({
            "mac": mac,
            "psid": int(psid),
            "psid_len": FIXED_PSID_LEN,
            "v6_prefix": FIXED_V6_PREFIX
        })

    config = {"devices": devices}

    with open(CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=2)

    push_config()

    return jsonify({"status": "Configuration sent"})

# -----------------------------
@app.route("/services_status.json")
def services():
    try:
        return jsonify(json.load(open(os.path.join(BASE_DIR, "services_status.json"))))
    except:
        return jsonify({})

@app.route("/output.json")
def output():
    try:
        return jsonify(json.load(open(os.path.join(BASE_DIR, "output.json"))))
    except:
        return jsonify({})

@app.route("/status.json")
def status():
    try:
        return jsonify(json.load(open(os.path.join(BASE_DIR, "status.json"))))
    except:
        return jsonify({"state": "unknown"})

# -----------------------------
@app.route("/query", methods=["GET"])
def query():
    """Single endpoint for curl queries — returns output + services + state."""
    result = {}
    try:
        result["output"] = json.load(open(os.path.join(BASE_DIR, "output.json")))
    except:
        result["output"] = {}
    try:
        result["services"] = json.load(open(os.path.join(BASE_DIR, "services_status.json")))
    except:
        result["services"] = {}
    try:
        result["status"] = json.load(open(os.path.join(BASE_DIR, "status.json")))
    except:
        result["status"] = {"state": "unknown"}
    return jsonify(result)

# -----------------------------
if __name__ == "__main__":
    start_mqtt()
    app.run(host="0.0.0.0", port=8282, debug=False, use_reloader=False)
