#!/bin/bash
gunicorn -w 1 -b 0.0.0.0:${APP_PORT:-80} project:app
