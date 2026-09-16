import time
import joblib
import numpy as np
import firebase_admin

from firebase_admin import credentials, db
from tensorflow.keras.models import load_model


# =========================
# SETTINGS
# =========================
FORECAST_HOURS = 4
CHECK_INTERVAL = 3600  # 1 hour

# =========================
# 1. Connect to Firebase
# =========================
cred = credentials.Certificate("serviceAccountKey.json")

if not firebase_admin._apps:
    firebase_admin.initialize_app(
        cred,
        {
            "databaseURL":
            "https://fyp-iot-project-48759-default-rtdb.asia-southeast1.firebasedatabase.app/"
        }
    )


# =========================
# 2. Load AQI model
# =========================
model = load_model("aqi_lstm_model.keras")
scaler = joblib.load("aqi_scaler.pkl")

# =========================
# 3. AQI calculation
# =========================
def calculate_aqi(concentration, c_low, c_high, i_low, i_high):

    return ((i_high - i_low) / (c_high - c_low)) * (concentration - c_low) + i_low

def calculate_pm25_aqi(concentration):

    if concentration <= 9.0:
        return calculate_aqi(
            concentration, 0.0, 9.0, 0, 50
        )

    elif concentration <= 35.4:
        return calculate_aqi(
            concentration, 9.1, 35.4, 51, 100
        )

    elif concentration <= 55.4:
        return calculate_aqi(
            concentration, 35.5, 55.4, 101, 150
        )

    elif concentration <= 125.4:
        return calculate_aqi(
            concentration, 55.5, 125.4, 151, 200
        )

    elif concentration <= 225.4:
        return calculate_aqi(
            concentration, 125.5, 225.4, 201, 300
        )

    elif concentration <= 325.4:
        return calculate_aqi(
            concentration, 225.5, 325.4, 301, 500
        )

    else:
        return 500


def calculate_pm10_aqi(concentration):

    if concentration <= 54:
        return calculate_aqi(
            concentration, 0, 54, 0, 50
        )

    elif concentration <= 154:
        return calculate_aqi(
            concentration, 55, 154, 51, 100
        )

    elif concentration <= 254:
        return calculate_aqi(
            concentration, 155, 254, 101, 150
        )

    elif concentration <= 354:
        return calculate_aqi(
            concentration, 255, 354, 151, 200
        )

    elif concentration <= 424:
        return calculate_aqi(
            concentration, 355, 424, 201, 300
        )

    elif concentration <= 604:
        return calculate_aqi(
            concentration, 425, 604, 301, 500
        )

    else:
        return 500


# =========================
# 4. Run one forecast cycle
# =========================
def run_prediction():

    print()
    print("======================================")
    print("Running AQI forecast...")
    print("======================================")

    # -------------------------
    # Read history
    # -------------------------
    history_ref = db.reference(
        "/history"
    )

    history_data = history_ref.get()

    if not history_data:
        print("No history data found.")
        return

    # -------------------------
    # Build AQI history
    # -------------------------
    records = []

    for key, value in history_data.items():

        if not isinstance(value, dict):
            continue

        if "pm25" not in value:
            continue

        if "pm10" not in value:
            continue

        timestamp = value.get("timestamp", int(key))

        pm25 = float(value["pm25"])

        pm10 = float(value["pm10"])

        pm25_aqi = calculate_pm25_aqi(pm25)

        pm10_aqi = calculate_pm10_aqi(pm10)

        overall_aqi = max(pm25_aqi,pm10_aqi)

        records.append(
            (
                int(timestamp),
                float(overall_aqi)
            )
        )

    records.sort(key=lambda x: x[0])

    # -------------------------
    # Need latest 12 AQI
    # -------------------------
    if len(records) < 12:

        print(
            f"Not enough data. "
            f"Need 12 readings, found {len(records)}."
        )

        return

    latest_12 = records[-12:]

    aqi_values = [
        value
        for timestamp, value
        in latest_12
    ]

    latest_history_timestamp = latest_12[-1][0]

    print("Latest 12 AQI values:")

    print(
        [
            round(value, 2)
            for value in aqi_values
        ]
    )

    # -------------------------
    # 4-hour forecast
    # -------------------------
    input_sequence = (aqi_values.copy())

    predictions = []

    for hour in range(FORECAST_HOURS):

        input_data = np.array(input_sequence).reshape(-1, 1)

        scaled_data = scaler.transform(input_data)

        X = scaled_data.reshape(1, 12, 1)

        prediction_scaled = model.predict(X, verbose=0)

        prediction = scaler.inverse_transform(prediction_scaled)[0][0]

        prediction = float(prediction)

        predictions.append(prediction)

        input_sequence = (input_sequence[1:] + [prediction])

    # -------------------------
    # Current AQI
    # -------------------------
    current_aqi = (aqi_values[-1])

    # -------------------------
    # Trend
    # -------------------------
    difference = (predictions[0] - current_aqi)

    if difference > 5:
        trend = "Increasing"

    elif difference < -5:
        trend = "Decreasing"

    else:
        trend = "Stable"

    # -------------------------
    # Display result
    # -------------------------
    print()

    print("Current AQI:", round(current_aqi, 2))

    print("Trend:", trend)

    print()

    print("4-hour AQI forecast:")

    for i, value in enumerate(
        predictions,
        start=1
    ):

        print(
            f"+{i} hour: "
            f"{value:.2f}"
        )

    # -------------------------
    # Upload to Firebase
    # -------------------------
    ai_ref = db.reference("/ai_result")

    ai_ref.set(
        {
            "current_aqi":
                round(current_aqi, 2),

            "predicted_aqi":
                round(predictions[0], 2),

            "forecast_aqi": {

                "hour_1":
                    round(predictions[0], 2),

                "hour_2":
                    round(predictions[1], 2),

                "hour_3":
                    round(predictions[2], 2),

                "hour_4":
                    round(predictions[3], 2),
            },

            "trend": trend,

            "forecast_horizon": "4 hours",

            "history_timestamp": latest_history_timestamp,

            "timestamp":
                int(
                    time.time()
                )
        }
    )

    print()
    print("AQI forecast uploaded to Firebase!")


# =========================
# 5. Continuous hourly forecast
# =========================
print("AQI Forecast Service Started")

print("A new forecast will be generated every 1 hour.")

while True:

    try:
        run_prediction()

    except Exception as e:
        print("Prediction error:", e)

    print()
    print("Waiting 1 hour before next forecast...")

    time.sleep(CHECK_INTERVAL)
