import sys
import os

# Add parent directory to sys.path to resolve root imports correctly on Vercel
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from main import app
