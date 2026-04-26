import paho.mqtt.client as mqtt
import os, json, time, threading

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

BROKER = "fd72:3456:789a::1"
PORT = 1883

TOPIC_CONFIG   = "rpi_jool/config"
TOPIC_STATUS   = "rpi_jool/status"
TOPIC_OUTPUT   = "rpi_jool/output"
TOPIC_SERVICES = "rpi_jool/services_status"

CONFIG_FILE   = os.path.join(BASE_DIR, "config_ui.json")
STATUS_FILE   = os.path.join(BASE_DIR, "status.json")
OUTPUT_FILE   = os.path.join(BASE_DIR, "output.json")
SERVICES_FILE = os.path.join(BASE_DIR, "services_status.json")

client = mqtt.Client(client_id=f"ui-{int(time.time())}")

# -----------------------------
def on_connect(client, userdata, flags, rc):
    if rc == 0:
        client.subscribe(TOPIC_STATUS)
        client.subscribe(TOPIC_OUTPUT)
        client.subscribe(TOPIC_SERVICES)

# -----------------------------
def on_message(client, userdata, msg):
    payload = msg.payload.decode()

    if msg.topic == TOPIC_STATUS:
        open(STATUS_FILE, "w").write(payload)

    elif msg.topic == TOPIC_OUTPUT:
        open(OUTPUT_FILE, "w").write(payload)

    elif msg.topic == TOPIC_SERVICES:
        try:
            # payload already has {"timestamp":..., "services":{...}} from check_services.sh
            json.loads(payload)  # validate JSON
            open(SERVICES_FILE, "w").write(payload)
        except Exception as e:
            print("services error:", e)

# -----------------------------
client.on_connect = on_connect
client.on_message = on_message

def mqtt_loop():
    while True:
        try:
            client.connect(BROKER, PORT)
            client.loop_forever()
        except:
            time.sleep(5)

def start_mqtt():
    threading.Thread(target=mqtt_loop, daemon=True).start()

# -----------------------------
def push_config():
    payload = json.load(open(CONFIG_FILE))
    payload["_meta"] = {"revision": int(time.time())}

    client.publish(TOPIC_CONFIG, json.dumps(payload), qos=1, retain=True)
