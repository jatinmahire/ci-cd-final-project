# CI/CD Tools and Practices Final Project Template

## Project name: ci-cd-final-project

A JavaScript/Express counter microservice with GitHub Actions continuous
integration and a six-stage Tekton/OpenShift delivery pipeline.

Based on the official [IBM JavaScript starter project](https://github.com/ibm-developer-skills-network/hdjqg-ci-cd-final-project-template).
The original Apache-2.0 license is retained.

## Continuous integration

[Workflow source](.github/workflows/workflow.yml)

The workflow runs on pushes and pull requests to `main`, and on manual dispatch:

1. Checkout the repository.
2. Set up Node.js 20 and npm caching.
3. Install the locked dependencies with `npm ci`.
4. Run ESLint with `npm run lint`.
5. Run the Jest unit tests with `npm test -- --runInBand --verbose`.

## Run locally or in the course lab

```bash
npm ci
npm run lint
npm test -- --runInBand --verbose
npm start
```

The service listens on port **8000** by default and prints **SERVICERUNNING**
inside the startup banner. `GET /health` returns `{"status":"OK"}`.

## REST API

| Method | Endpoint | Purpose |
| --- | --- | --- |
| GET | `/` | Service information |
| GET | `/health` | Health check |
| GET | `/counters` | List counters |
| POST | `/counters/:name` | Create a counter |
| GET | `/counters/:name` | Read a counter |
| PUT | `/counters/:name` | Increment a counter |
| DELETE | `/counters/:name` | Delete a counter |

Counter storage is in memory and resets when the application restarts.

## OpenShift delivery pipeline

- [Custom cleanup, ESLint, and Jest tasks](.tekton/tasks.yml)
- [Pipeline definition](.tekton/pipeline.yml)
- [PersistentVolumeClaim definition](.tekton/pvc.yml)
- [Course-lab setup and execution script](bin/deploy-openshift.sh)

The pipeline executes these stages sequentially:

`cleanup → git-clone → eslint → jest → buildah → deploy`

The `jest` stage uses the custom `jest-test` task. The `deploy` stage uses the
Tekton `openshift-client` task. All source-based stages share the `output`
workspace backed by `oc-lab-pvc`, requesting **1Gi** from the
**skills-network-learner** storage class.

In an authenticated course OpenShift lab, run:

```bash
git clone https://github.com/jatinmahire/ci-cd-final-project.git
cd ci-cd-final-project
bash bin/deploy-openshift.sh
```

The script checks the lab namespace, installs missing namespaced catalog tasks,
applies the PVC and pipeline, starts a PipelineRun with a unique image tag, and
collects real logs. It does not claim a successful run unless Tekton reports
`Succeeded=True` and the deployed application's logs contain `SERVICERUNNING`
and port `8000`. Buildah requires the execution permissions provided by the lab.

The course parameter `-v` is translated to Jest's `--verbose` flag so the task
executes the tests rather than printing a version number.

## Assignment submission links

1. [README.md](https://github.com/jatinmahire/ci-cd-final-project/blob/main/README.md)
2. [GitHub workflow](https://github.com/jatinmahire/ci-cd-final-project/blob/main/.github/workflows/workflow.yml)
3. [Tekton tasks](https://github.com/jatinmahire/ci-cd-final-project/blob/main/.tekton/tasks.yml)

GitHub Actions evidence must come from an actual completed workflow run.
OpenShift screenshots and application logs must come from the authenticated
course cluster; YAML definitions alone are not execution evidence.
