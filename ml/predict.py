import joblib
import pandas as pd

# Load trained model
saved = joblib.load("termite_rf_model.joblib")

# Test sensor data
data = {
    "dominant_frequency_hz": 4200,
    "amplitude": 0.7,
    "rms": 0.45,
    "snr_db": 14,
    "pulse_rate_hz": 18
}

row = pd.DataFrame([data])

# Prediction
probability = saved["model"].predict_proba(
    row[saved["features"]]
)[0, 1]

print("==============================")
print("       TERMIGUARD ML")
print("==============================")
print("Frequency:", data["dominant_frequency_hz"], "Hz")
print("Amplitude:", data["amplitude"])
print("RMS:", data["rms"])
print("SNR:", data["snr_db"], "dB")
print("Pulse Rate:", data["pulse_rate_hz"], "Hz")
print()

if probability >= 0.5:
    print("RESULT: TERMITE ACTIVITY")
else:
    print("RESULT: NO TERMITE ACTIVITY")

print("PROBABILITY:", round(probability * 100, 2), "%")
print("==============================")