"""A small, real ML model: logistic regression on the Iris dataset.

Trains in well under a second and needs no network access or downloaded
weights, which matters for a cold-start demo running on a private cluster.
"""

from sklearn.datasets import load_iris
from sklearn.linear_model import LogisticRegression

FEATURE_NAMES = [
    "sepal_length_cm",
    "sepal_width_cm",
    "petal_length_cm",
    "petal_width_cm",
]


class IrisClassifier:
    def __init__(self) -> None:
        iris = load_iris()
        self.model = LogisticRegression(max_iter=200)
        self.model.fit(iris.data, iris.target)
        self.class_names = list(iris.target_names)

    def predict(self, features: list[float]) -> dict:
        prediction = self.model.predict([features])[0]
        probabilities = self.model.predict_proba([features])[0]
        return {
            "class": self.class_names[prediction],
            "probabilities": {
                name: round(float(prob), 4)
                for name, prob in zip(self.class_names, probabilities)
            },
        }
