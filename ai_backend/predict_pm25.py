import time
import joblib
import numpy as np
import firebase_admin

from firebase_admin import credentials, db
from tensorflow.keras.models import load_model


# =========================
# 1. Connect to Firebase
# =========================

cred = credentials.Certificate(
    "serviceAccountKey.json"
)

firebase_admin.initialize_app(
    cred,
    {
        "databaseURL":
        "https://fyp-iot-project-48759-default-rtdb.asia-southeast1.firebasedatabase.app/"
    }
)


# =========================
# 2. Load trained AI model
# =========================

model = load_model(
    "pm25_lstm_model.keras"
)

scaler = joblib.load(
    "pm25_scaler.pkl"
)


# =========================
# 3. Read history from Firebase
# =========================

history_ref = db.reference(
    "/history"
)

history_data = history_ref.get()

if not history_data:
    print("No history data found.")
    exit()


# =========================
# 4. Extract PM2.5 records
# =========================

records = []

for key, value in history_data.items():

    if not isinstance(value, dict):
        continue

    if "pm25" not in value:
        continue

    timestamp = value.get(
        "timestamp",
        int(key)
    )

    records.append(
        (
            int(timestamp),
            float(value["pm25"])
        )
    )


# Sort from oldest to newest
records.sort(
    key=lambda x: x[0]
)


# =========================
# 5. Need latest 12 readings
# =========================

if len(records) < 12:
    print(
        f"Not enough data. "
        f"Need 12 readings, found {len(records)}."
    )
    exit()


latest_12 = records[-12:]

pm25_values = [
    value
    for timestamp, value in latest_12
]


print(
    "Latest 12 PM2.5 values:"
)

print(
    pm25_values
)


# =========================
# 6. MULTI-HOUR FORECAST
# =========================

FORECAST_HOURS = 4

input_sequence = (
    pm25_values.copy()
)

predictions = []


for hour in range(
    FORECAST_HOURS
):

    # Convert latest 12 values
    # into NumPy array
    input_data = np.array(
        input_sequence
    ).reshape(
        -1,
        1
    )


    # Scale input
    scaled_data = scaler.transform(
        input_data
    )


    # LSTM input shape:
    # (samples, time_steps, features)
    X = scaled_data.reshape(
        1,
        12,
        1
    )


    # Predict next hour
    prediction_scaled = (
        model.predict(
            X,
            verbose=0
        )
    )


    # Convert prediction back
    # to original PM2.5 scale
    prediction = (
        scaler.inverse_transform(
            prediction_scaled
        )[0][0]
    )


    prediction = float(
        prediction
    )


    predictions.append(
        prediction
    )


    # Remove oldest reading
    # and add predicted value
    input_sequence = (
        input_sequence[1:]
        + [prediction]
    )


# =========================
# 7. CURRENT VALUE
# =========================

current_pm25 = (
    pm25_values[-1]
)


# =========================
# 8. DETERMINE TREND
# =========================

# Compare current value
# with first-hour prediction

difference = (
    predictions[0]
    - current_pm25
)


if difference > 2:

    trend = "Increasing"

elif difference < -2:

    trend = "Decreasing"

else:

    trend = "Stable"


# =========================
# 9. DISPLAY RESULTS
# =========================

print()

print(
    "Current PM2.5:",
    current_pm25
)

print(
    "Trend:",
    trend
)

print()

print(
    "4-hour PM2.5 forecast:"
)


for i, value in enumerate(
    predictions,
    start=1
):

    print(
        f"+{i} hour: "
        f"{value:.2f} µg/m³"
    )


# =========================
# 10. Upload AI result
# =========================

ai_ref = db.reference(
    "/ai_result"
)


ai_ref.set(
    {
        "current_pm25":
            round(
                float(current_pm25),
                2
            ),

        # Keep this for your
        # existing Flutter code
        "predicted_pm25":
            round(
                predictions[0],
                2
            ),

        # New multi-hour forecast
        "forecast_pm25": {

            "hour_1":
                round(
                    predictions[0],
                    2
                ),

            "hour_2":
                round(
                    predictions[1],
                    2
                ),

            "hour_3":
                round(
                    predictions[2],
                    2
                ),

            "hour_4":
                round(
                    predictions[3],
                    2
                ),
        },

        "trend":
            trend,

        "forecast_horizon":
            "4 hours",

        "timestamp":
            int(
                time.time()
            )
    }
)


print()

print(
    "4-hour prediction "
    "uploaded to Firebase!"
)