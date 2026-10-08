"""Train the Termiguard model on labeled scans exported from the app.

Usage (from the ml folder):
    python train_real.py termiguard_scans_1234567890.csv
    python train_real.py termiguard_scans_1234567890.csv --binary   # termite vs not

Every scan you export from the app is one row; the features are only
things the ESP32 really sends.
"""
import sys

import joblib
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report, confusion_matrix
from sklearn.model_selection import StratifiedKFold, cross_val_predict

FEATURES = [
    "click_count",
    "click_rate_hz",
    "db_mean",
    "db_max",
    "db_std",
    "freq_mean_hz",
    "freq_median_hz",
    "freq_std_hz",
    "gap_mean_s",
    "gap_std_s",
]

args = [a for a in sys.argv[1:] if not a.startswith("--")]
binary = "--binary" in sys.argv
if not args:
    sys.exit("usage: python train_real.py <termiguard_scans_....csv> [--binary]")

df = pd.read_csv(args[0])
X = df[FEATURES]
y = df["label"]
if binary:
    y = y.where(y == "termite", "not_termite")

print("Scans per label:")
print(y.value_counts().to_string())
if y.nunique() < 2:
    sys.exit("Need at least two different labels to train.")

clf = RandomForestClassifier(
    n_estimators=300, random_state=42, class_weight="balanced"
)

# Cross-validation: every scan is predicted by a model that never saw it.
folds = min(5, int(y.value_counts().min()))
if folds >= 2:
    cv = StratifiedKFold(n_splits=folds, shuffle=True, random_state=42)
    pred = cross_val_predict(clf, X, y, cv=cv)
    print(f"\n{folds}-fold cross-validation:")
    print(classification_report(y, pred, zero_division=0))
    labels = sorted(y.unique())
    print("Confusion matrix (rows = true, columns = predicted):")
    print(labels)
    print(confusion_matrix(y, pred, labels=labels))
else:
    print("\nToo few scans in the smallest class for cross-validation. "
          "Record more before trusting any number.")

clf.fit(X, y)
joblib.dump({"model": clf, "features": FEATURES}, "termite_rf_real.joblib")
print("\nSaved termite_rf_real.joblib")
