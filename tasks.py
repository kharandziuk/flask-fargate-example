from invoke import task
from pathlib import Path
from dotenv import load_dotenv
import os

load_dotenv()


@task
def dependencies(c):
    c.run("pip install -r requirements.txt")


@task(dependencies)
def validate_code(c):
    c.run("pre-commit install")
    c.run("pre-commit run --all-files")


@task
def develop(c):
    c.run("docker-compose up")
