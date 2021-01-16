from invoke import task
from pathlib import Path
from dotenv import load_dotenv
import os

load_dotenv()



@task
def develop(c):
    c.run('docker-compose up')
