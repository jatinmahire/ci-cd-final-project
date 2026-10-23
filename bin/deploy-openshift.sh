#!/usr/bin/env bash
# Run only in the authenticated course lab; collect actual cluster evidence.
set -euo pipefail

cd "$(dirname "$0")/.."
for tool in oc tkn; do
  command -v "$tool" >/dev/null || {
    echo "$tool is missing. Open the CI/CD final-project lab with OpenShift." >&2
    exit 1
  }
done

if ! oc whoami >/dev/null 2>&1; then
  echo "OpenShift is not connected in this terminal." >&2
  echo "Open the lab's Skills Network Toolbox > Cloud > OpenShift, start the cluster," >&2
  echo "and use its configured terminal or login instructions. Then rerun this script." >&2
  exit 1
fi

NAMESPACE=$(oc project -q 2>/dev/null || true)
if [[ -z "$NAMESPACE" ]]; then
  if ! PROJECTS=$(oc projects -q); then
    echo "Unable to list your OpenShift projects. Check the lab's OpenShift connection." >&2
    exit 1
  fi
  LAB_PROJECTS=()
  while IFS= read -r project; do
    case "$project" in
      sn-labs-*|skills-network-*|lab-*) LAB_PROJECTS+=("$project") ;;
    esac
  done <<< "$PROJECTS"
  if [[ ${#LAB_PROJECTS[@]} -eq 1 ]]; then
    oc project "${LAB_PROJECTS[0]}"
    NAMESPACE=${LAB_PROJECTS[0]}
  else
    echo "No active OpenShift project. Available projects:" >&2
    printf '%s\n' "$PROJECTS" >&2
    echo "Run: oc project YOUR_COURSE_PROJECT_NAME" >&2
    echo "Then rerun: bash bin/deploy-openshift.sh" >&2
    exit 1
  fi
fi
case "$NAMESPACE" in
  sn-labs-*|skills-network-*|lab-*) ;;
  *) echo "Select your course lab namespace before running this script: $NAMESPACE" >&2; exit 1 ;;
esac
mkdir -p evidence

echo "Preparing the CI/CD pipeline in course namespace $NAMESPACE"
oc apply -f .tekton/tasks.yml

# Use existing namespaced Tasks when available. Install missing tasks from the
# official Tekton catalog; no credentials are stored in this repository.
if ! oc get task git-clone >/dev/null 2>&1; then
  oc apply -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/git-clone/0.9/git-clone.yaml
fi
if ! oc get task buildah >/dev/null 2>&1; then
  oc apply -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/buildah/0.9/buildah.yaml
fi
if ! oc get task openshift-client >/dev/null 2>&1; then
  oc apply -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/openshift-client/0.2/openshift-client.yaml
fi

oc apply -f .tekton/pvc.yml
oc apply -f .tekton/pipeline.yml
if ! oc get serviceaccount pipeline >/dev/null 2>&1; then
  oc create serviceaccount pipeline
fi
oc create rolebinding cicd-pipeline-editor --clusterrole=edit \
  --serviceaccount="$NAMESPACE:pipeline" --dry-run=client -o yaml | oc apply -f -
oc create rolebinding cicd-pipeline-image-builder --clusterrole=system:image-builder \
  --serviceaccount="$NAMESPACE:pipeline" --dry-run=client -o yaml | oc apply -f -
oc create imagestream counter-service --dry-run=client -o yaml | oc apply -f -

BUILD_IMAGE="image-registry.openshift-image-registry.svc:5000/$NAMESPACE/counter-service:run-$(date +%s)"
RUN_NAME=$(oc create -f - -o jsonpath='{.metadata.name}' <<YAML
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  generateName: ci-cd-final-project-run-
spec:
  pipelineRef:
    name: ci-cd-final-project
  serviceAccountName: pipeline
  timeouts:
    pipeline: 20m
  params:
    - name: repo-url
      value: https://github.com/jatinmahire/ci-cd-final-project.git
    - name: revision
      value: main
    - name: app-name
      value: counter-service
    - name: build-image
      value: $BUILD_IMAGE
  workspaces:
    - name: output
      persistentVolumeClaim:
        claimName: oc-lab-pvc
YAML
)

printf '%s\n' "$RUN_NAME" > evidence/pipelinerun-name.txt
echo "Started PipelineRun: $RUN_NAME"
tkn pipelinerun logs "$RUN_NAME" -f | tee evidence/oc-pipeline-run.log
SUCCEEDED=$(oc get pipelinerun "$RUN_NAME" -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}')
if [[ "$SUCCEEDED" != "True" ]]; then
  echo "PipelineRun did not succeed. Review its real logs before submitting evidence." >&2
  exit 1
fi

oc rollout status deployment/counter-service --timeout=180s
oc logs deployment/counter-service --tail=50 | tee evidence/oc-pipeline-application-logs.txt
grep -q 'SERVICERUNNING' evidence/oc-pipeline-application-logs.txt
grep -q 'port 8000' evidence/oc-pipeline-application-logs.txt
oc get pvc oc-lab-pvc -o yaml > evidence/pvc-details.yml
oc get pipelinerun "$RUN_NAME" -o yaml > evidence/successful-pipelinerun.yml

echo "Real OpenShift run succeeded. Text evidence is in evidence/."
echo "Capture the PVC details and Pipeline/PipelineRun views in the OpenShift console."
