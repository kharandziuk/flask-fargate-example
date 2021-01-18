import base64
import datetime
import json
import uuid
import logging
import os

from flask import Flask, render_template, request, redirect

from dotenv import load_dotenv

load_dotenv()


app = Flask(__name__)

APP_PORT = os.environ.get("APP_PORT", 80)


@app.route("/")
def index():
    return render_template(
        "main.html",
        title="sample app",
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=APP_PORT)
