from invoke import task
from pathlib import Path
from dotenv import load_dotenv
import os
import json

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


@task
def get_identity(c):
    c.run("aws sts get-caller-identity")


@task(get_identity)
def apply_repos(c):
    with c.cd("repos"):
        c.run("terraform init && terraform apply --auto-approve")


@task
def destroy_repos(c):
    with c.cd("repos"):
        c.run("terraform init && terraform destroy --auto-approve")


@task(get_identity)
def apply_infra(c):
    with c.cd("infrastructure"):
        c.run("terraform init && terraform apply --auto-approve")


@task
def destroy_infra(c):
    with c.cd("infrastructure"):
        c.run("terraform init && terraform destroy --auto-approve")


@task
def login(c):
    # FIXME: hardcoded region
    c.run(
        f"aws ecr get-login-password --region eu-central-1 | "
        "docker login --username AWS --password-stdin 818979561351.dkr.ecr.eu-central-1.amazonaws.com"
    )


@task(login)
def build(c):
    with c.cd("repos"):
        repo_url = c.run("terraform output backend_repo_url").stdout.split()[0]
    if not repo_url:
        return
    c.run(f"docker build -t {repo_url} ./backend")
    c.run(f"docker push {repo_url}")


@task
def force_deployment(c):
    result = c.run(
        "aws ecs list-tasks --cluster default --region $AWS_REGION  --service-name test-api | jq '.taskArns'"
    ).stdout.strip()
    for servide_id in json.loads(result):
        c.run(f"aws ecs stop-task --region $AWS_REGION --task {servide_id}")
    c.run(
        "aws ecs update-service --region=$AWS_REGION --cluster default  --service test-api --force-new-deployment"
    )


@task(get_identity)
def together(c):
    apply_repos(c)
    build(c)
    force_deployment(c)
    apply_infra(c)


@task(get_identity)
def destroy_all(c):
    destroy_infra(c)
    destroy_repos(c)
