import joblib, pandas as pd

saved = joblib.load("termite_rf_model.joblib")
row = pd.DataFrame([{"dominant_frequency_hz": 4200, "amplitude": 0.7,
                     "rms": 0.45, "snr_db": 14, "pulse_rate_hz": 18}])
print("Probability of termite:", saved["model"].predict_proba(row[saved["features"]])[0, 1])
