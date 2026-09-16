import os, time, threading, firebase_admin
from firebase_admin import credentials, db
from google import genai

# =========================
# SETTINGS
# =========================
CHECK_INTERVAL = 60
AQI_CHANGE_THRESHOLD = 10

# =========================
# FIREBASE + GENAI
# =========================
cred = credentials.Certificate("serviceAccountKey.json")

if not firebase_admin._apps:
    firebase_admin.initialize_app(cred, {
        "databaseURL": "https://fyp-iot-project-48759-default-rtdb.asia-southeast1.firebasedatabase.app/"
    })

api_key = os.getenv("GEMINI_API_KEY")
client = genai.Client(api_key=api_key) if api_key else None

# =========================
# AQI HELPERS
# =========================
def calculate_aqi(c, c_low, c_high, i_low, i_high):
    return ((i_high - i_low) / (c_high - c_low)) * (c - c_low) + i_low

def calculate_pm25_aqi(c):
    if c <= 9.0: return calculate_aqi(c, 0.0, 9.0, 0, 50)
    if c <= 35.4: return calculate_aqi(c, 9.1, 35.4, 51, 100)
    if c <= 55.4: return calculate_aqi(c, 35.5, 55.4, 101, 150)
    if c <= 125.4: return calculate_aqi(c, 55.5, 125.4, 151, 200)
    if c <= 225.4: return calculate_aqi(c, 125.5, 225.4, 201, 300)
    if c <= 325.4: return calculate_aqi(c, 225.5, 325.4, 301, 500)
    return 500

def calculate_pm10_aqi(c):
    if c <= 54: return calculate_aqi(c, 0, 54, 0, 50)
    if c <= 154: return calculate_aqi(c, 55, 154, 51, 100)
    if c <= 254: return calculate_aqi(c, 155, 254, 101, 150)
    if c <= 354: return calculate_aqi(c, 255, 354, 151, 200)
    if c <= 424: return calculate_aqi(c, 355, 424, 201, 300)
    if c <= 604: return calculate_aqi(c, 425, 604, 301, 500)
    return 500

def get_aqi_category(aqi):
    if aqi <= 50: return "Good"
    if aqi <= 100: return "Moderate"
    if aqi <= 150: return "Poor"
    if aqi <= 200: return "Unhealthy"
    if aqi <= 300: return "Very Unhealthy"
    return "Hazardous"

# =========================
# FALLBACK RECOMMENDATION
# =========================
def get_local_recommendation(aqi, status, pollutant):

    if status == "Good":
        return f"Air quality is currently Good with an estimated AQI of {aqi:.0f}. Normal indoor activities can continue; keep an eye on the app for changes."

    if status == "Moderate":
        return f"Air quality is Moderate with an estimated AQI of {aqi:.0f}, mainly influenced by {pollutant}. If possible, reduce particle-producing activities and ventilate when the surrounding air is cleaner."

    if status == "Poor":
        return f"Air quality is Poor with an estimated AQI of {aqi:.0f}, mainly influenced by {pollutant}. Consider reducing prolonged exposure in this area and move to cleaner indoor air if available."

    if status == "Unhealthy":
        return f"Air quality is Unhealthy with an estimated AQI of {aqi:.0f}, mainly influenced by {pollutant}. Limit time in the affected area and move to cleaner air if possible."

    if status == "Very Unhealthy":
        return f"Air quality is Very Unhealthy with an estimated AQI of {aqi:.0f}. Avoid unnecessary time in the affected area and move to cleaner air if possible."

    return f"Air quality is Hazardous with an estimated AQI of {aqi:.0f}. Avoid unnecessary exposure to the affected area and move to cleaner air if possible."

# =========================
# AI RECOMMENDATION
# =========================
last_status = None
last_aqi = None

def generate_recommendation():
    global last_status, last_aqi

    data = db.reference("/environment").get()

    if not data:
        print("No environment data found.")
        return

    pm25 = float(data.get("pm25", 0))
    pm10 = float(data.get("pm10", 0))
    pm25_aqi = calculate_pm25_aqi(pm25)
    pm10_aqi = calculate_pm10_aqi(pm10)
    overall_aqi = max(pm25_aqi, pm10_aqi)
    status = get_aqi_category(overall_aqi)
    pollutant = "PM2.5" if pm25_aqi >= pm10_aqi else "PM10"

    print("\n==============================")
    print("Checking current air quality...")
    print("==============================")

    print(f"Overall AQI: {overall_aqi:.0f}")

    print(f"AQI category: {status}")

    print(f"Main pollutant: {pollutant}")

    if last_status is None:
        reason = "First recommendation"

    elif status != last_status:
        reason = f"AQI category changed from {last_status} to {status}"

    elif last_aqi is not None and abs(overall_aqi - last_aqi) >= AQI_CHANGE_THRESHOLD:
        reason = f"Overall AQI changed by {abs(overall_aqi - last_aqi):.0f} points"

    else:
        print("No significant change. Skipping AI generation.")

        return

    prompt = f"""
You write recommendations for people who use the EnviroSense mobile application.

Current estimated overall AQI: {overall_aqi:.0f}
Current AQI category: {status}
Main pollutant: {pollutant}

Generate a short recommendation for the person viewing the app.

Requirements:
- Write 1 to 3 short sentences.
- Address the app user, not the developer, researcher, or system owner.
- Give practical actions the user can take in response to the current air quality.
- Base the advice only on the overall AQI, AQI category, and main pollutant.
- If Good, briefly reassure the user.
- If Moderate, give mild practical advice.
- If Poor or Unhealthy, suggest reducing exposure and seeking cleaner air where practical.
- If Very Unhealthy or Hazardous, give a clear warning and recommend moving to cleaner air where possible.
- Do not tell the user to inspect, repair, recalibrate, reposition, restart, or modify sensors, ESP32, wiring, Firebase, software, or hardware.
- Do not mention ADC values, code, APIs, LSTM, forecasting, sensor maintenance, or system maintenance.
- Do not mention that you are an AI.
- Do not make medical diagnoses.
"""

    recommendation = None

    if client:
        try:
            response = client.models.generate_content(model="gemini-3.7-flash", contents=prompt)
            recommendation = response.text.strip()

        except Exception as e:
            print("AI generation error:", e)

    if not recommendation:
        print("Using local fallback recommendation.")
        recommendation = get_local_recommendation(overall_aqi, status, pollutant)

    print("\nRecommendation:")
    print(recommendation)

    db.reference("/ai_recommendation").set({
        "status": status,
        "overall_aqi": round(overall_aqi),
        "main_pollutant": pollutant,
        "recommendation": recommendation,
        "reason": reason,
        "timestamp": int(time.time())
    })

    last_status = status
    last_aqi = overall_aqi
    print("Recommendation uploaded to Firebase!")

# =========================
# ALERT HELPERS
# =========================
def get_local_alert(event_type, current_pm25, previous_pm25=None,
                    predicted_aqi=None, forecast_category=None):

    if event_type == "sudden_spike":
        return f"PM2.5 suddenly increased from {previous_pm25:.0f} to {current_pm25:.0f} µg/m³. Consider moving to cleaner air and reducing exposure to the affected area."

    if event_type == "forecast_update":
        return f"Future air quality is forecast to be {forecast_category} with an AQI of {predicted_aqi:.0f}. Plan activities accordingly and reduce exposure if conditions worsen."

    if event_type == "current_bad":
        return f"Current air quality is poor with PM2.5 at {current_pm25:.0f} µg/m³. Consider reducing exposure and moving to cleaner air if possible."

    return None

def generate_alert_message(event_type, current_pm25, previous_pm25=None,
                           predicted_aqi=None, forecast_category=None, trend=None):

    if event_type == "sudden_spike":
        details = f"Event: Sudden PM2.5 increase\nPrevious PM2.5: {previous_pm25:.1f} µg/m³\nCurrent PM2.5: {current_pm25:.1f} µg/m³"

    elif event_type == "forecast_update":
        details = f"Event: Future air quality forecast update\nPredicted AQI: {predicted_aqi:.0f}\nForecast category: {forecast_category}\nTrend: {trend}"

    elif event_type == "current_bad":
        details = f"Event: Current poor air quality\nCurrent PM2.5: {current_pm25:.1f} µg/m³"

    else:
        return None

    prompt = f"""
You write mobile alert messages for people who use the EnviroSense application.

{details}

Requirements:
- Write 1 to 2 short sentences.
- Address the app user, not the developer or system owner.
- Clearly explain what was detected and give one practical user action when appropriate.
- Focus on exposure, activities, ventilation, or moving to cleaner air where practical.
- Do not tell the user to inspect, repair, recalibrate, move, restart, or modify sensors, ESP32, wiring, Firebase, software, or other hardware.
- Do not mention code, APIs, LSTM, sensor maintenance, or that you are an AI.
- Do not claim a pollution source such as smoke or fire unless it is known.
- Do not make medical diagnoses.
"""

    if client:
        try:
            response = client.models.generate_content(model="gemini-3.7-flash", contents=prompt)

            if response.text.strip():
                return response.text.strip()

        except Exception as e:
            print("AI alert generation error:", e)

    return get_local_alert(event_type, current_pm25, previous_pm25,
                           predicted_aqi, forecast_category)

def save_ai_alert(event_type, title, message):

    db.reference("/ai_alert").set({
        "type": event_type,
        "title": title,
        "message": message,
        "timestamp": int(time.time())
    })

    print("AI alert uploaded to Firebase!")

def check_alert_request():

    request_ref = db.reference("/alert_request")
    data = request_ref.get()

    if not data:
        return

    event_type = data.get("type")
    current_pm25 = float(data.get("current_pm25", 0))
    previous_pm25 = data.get("previous_pm25")
    predicted_aqi = data.get("predicted_aqi")
    forecast_category = data.get("forecast_category")
    trend = data.get("trend")

    previous_pm25 = float(previous_pm25) if previous_pm25 is not None else None
    predicted_aqi = float(predicted_aqi) if predicted_aqi is not None else None

    message = generate_alert_message(
        event_type, current_pm25, previous_pm25,
        predicted_aqi, forecast_category, trend
    )

    if message is None:
        return

    if event_type == "sudden_spike":
        title = "Sudden Air Quality Change"

    elif event_type == "forecast_update":
        if forecast_category == "Good":
            title = "Future Air Quality Looks Good"
        elif forecast_category == "Moderate":
            title = "Future Air Quality Moderate"
        else:
            title = "Future Air Quality Warning"

    elif event_type == "current_bad":
        title = "Poor Air Quality Detected"

    else:
        title = "Air Quality Alert"

    save_ai_alert(event_type, title, message)
    request_ref.delete()

# =========================
# CONTINUOUS SERVICE
# =========================
def fast_alert_loop():

    while True:
        try:
            check_alert_request()
        except Exception as e:
            print("Alert loop error:", e)
        time.sleep(2)

threading.Thread(target=fast_alert_loop, daemon=True).start()

print("AI Recommendation Service Started")
print("Firebase checked every 1 minute.")
print("GenAI is called only when air quality changes significantly.")

if not api_key:
    print("GEMINI_API_KEY not found. Local fallback recommendations will be used.")

while True:

    try:
        generate_recommendation()
    except Exception as e:
        print("Unexpected error:", e)

    print("\nWaiting 1 minute...")
    time.sleep(CHECK_INTERVAL)
