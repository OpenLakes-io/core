#! /bin/bash
set -e

echo "Commencing OpenLakes installation..."
echo ""
echo "Deploying layer 01 infrastructure"
helm install openlakes-infrastructure ./layers/01-infrastructure --namespace openlakes --create-namespace
sleep 5
echo ""
echo "Deploying layer 02 compute"
helm install openlakes-compute ./layers/02-compute --namespace openlakes
sleep 5
echo ""
echo "Deploying layer 03 streaming"
helm install openlakes-streaming ./layers/03-streaming --namespace openlakes
sleep 5
echo ""
echo "Deploying layer 04 orchestration"
helm install openlakes-orchestration ./layers/04-orchestration --namespace openlakes
sleep 5
echo ""
echo "Deploying layer 05 analytics"
helm install openlakes-analytics ./layers/05-analytics --namespace openlakes
sleep 5
echo ""
echo "Deploying layer 06 ingestion"
helm install openlakes-ingestion ./layers/06-ingestion --namespace openlakes
sleep 5
echo ""
echo "Deploying layer 07 catalog"
helm install openlakes-catalog ./layers/07-catalog --namespace openlakes