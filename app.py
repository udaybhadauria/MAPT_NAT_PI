from flask import Flask, request, jsonify, render_template, session, redirect, url_for
from functools import wraps
import json
import os
from datetime import timedelta
from mqtt_controller import push_config, start_mqtt

app = Flask(__name__, static_folder="templates")
app.secret_key = "mapt_secret_key_2026"  # Change this to a strong secret in production
app.config['SESSION_COOKIE_SECURE'] = False  # Set to True in production with HTTPS
app.config['SESSION_COOKIE_HTTPONLY'] = True
app.config['SESSION_COOKIE_SAMESITE'] = 'Lax'
app.config['PERMANENT_SESSION_LIFETIME'] = timedelta(minutes=35)  # 35 mins idle timeout

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(BASE_DIR, "config_ui.json")

FIXED_PSID_LEN = 6
FIXED_V6_PREFIX = "2600:8809:a505:91d0::/60"

# Simple credentials (change these in production or use a database)
VALID_USERS = {
    "admin": "admin123",
    "user": "user123"
}

# Login required decorator
def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'user' not in session:
            return redirect(url_for('login'))
        session.permanent = True
        app.permanent_session_lifetime = timedelta(minutes=35)
        return f(*args, **kwargs)
    return decorated_function

# ---- LOGIN ROUTES ----
@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form.get("username")
        password = request.form.get("password")
        
        if username in VALID_USERS and VALID_USERS[username] == password:
            session['user'] = username
            session.permanent = True
            return redirect(url_for('index'))
        else:
            error = "Invalid username or password"
            return render_template("login.html", error=error)
    
    return render_template("login.html")

@app.route("/logout", methods=["GET"])
def logout():
    session.clear()
    return redirect(url_for('login'))

# ----
@app.route("/", methods=["GET"])
@login_required
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
    username = session.get('user', 'User')
    return render_template("index.html", config=dummy_config, username=username)

# -----------------------------
@app.route("/apply", methods=["POST"])
@login_required
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
