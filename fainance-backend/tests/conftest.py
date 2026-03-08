import sys
import os

# fainance-backend/ zum Python-Pfad hinzufügen damit
# `from models import ...` in den Tests funktioniert
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))