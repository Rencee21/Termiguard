import sys, joblib, pandas as pd
from sklearn.ensemble import RandomForestClassifier

FEATURES = ["dominant_frequency_hz", "amplitude", "rms", "snr_db", "pulse_rate_hz"]
df = pd.read_csv(sys.argv[1])
y = (df["label"] == "Termite").astype(int)
model = RandomForestClassifier(n_estimators=300, random_state=42).fit(df[FEATURES], y)
joblib.dump({"model": model, "features": FEATURES}, "termite_rf_model.joblib")
print("Saved termite_rf_model.joblib")
