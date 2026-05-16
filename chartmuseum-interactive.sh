cat << 'EOF' > ~/personal_repo/devops-tool/chartmuseum-interactive.sh
#!/bin/bash

# Colors for better UX
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

CHARTMUSEUM_URL="http://chartmuseum.localhost"

# Function to display header
show_header() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           ChartMuseum Interactive Management Tool         ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo -e "${GREEN}Repository:${NC} $CHARTMUSEUM_URL"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# Function to list all charts
list_charts() {
    echo -e "${BLUE}📦 Listing all charts...${NC}\n"
    response=$(curl -s "$CHARTMUSEUM_URL/api/charts")
    
    if [ "$response" = "{}" ] || [ "$response" = "" ]; then
        echo -e "${YELLOW}No charts found in repository.${NC}"
    else
        echo "$response" | jq -r 'to_entries[] | "\(.key) [\(.value | length) version(s)]"' 2>/dev/null || echo "$response"
    fi
    echo ""
}

# Function to show chart details
show_chart_details() {
    local chart=$1
    echo -e "${BLUE}🔍 Details for chart: ${CYAN}$chart${NC}\n"
    
    response=$(curl -s "$CHARTMUSEUM_URL/api/charts/$chart")
    
    if [ "$response" = "{}" ] || [ "$response" = "null" ]; then
        echo -e "${RED}Chart '$chart' not found.${NC}"
    else
        echo "$response" | jq -r '.[] | "Version: \(.version)\nDescription: \(.description)\nApp Version: \(.appVersion)\nCreated: \(.created)\nDigest: \(.digest[0:20])...\n---"' 2>/dev/null || echo "$response"
    fi
    echo ""
}

# Function to push a chart
push_chart() {
    echo -e "${BLUE}📤 Push a Helm Chart${NC}"
    echo -e "${YELLOW}Enter the path to .tgz file (or press Enter to cancel):${NC}"
    read -p "> " chart_path
    
    if [ -z "$chart_path" ]; then
        echo -e "${YELLOW}Cancelled.${NC}"
        return
    fi
    
    if [ ! -f "$chart_path" ]; then
        echo -e "${RED}File not found: $chart_path${NC}"
        return
    fi
    
    echo -e "${YELLOW}Pushing chart...${NC}"
    response=$(curl -s -X POST --data-binary "@$chart_path" "$CHARTMUSEUM_URL/api/charts")
    
    if echo "$response" | grep -q "saved\|created"; then
        echo -e "${GREEN}✓ Chart pushed successfully!${NC}"
    else
        echo -e "${RED}✗ Failed to push chart: $response${NC}"
    fi
    echo ""
}

# Function to download a chart
download_chart() {
    echo -e "${BLUE}📥 Download a Chart${NC}"
    echo -e "${YELLOW}Available charts:${NC}"
    list_charts
    
    echo -e "\n${YELLOW}Enter chart name and version (format: chartname/version):${NC}"
    read -p "> " chart_version
    
    if [ -z "$chart_version" ]; then
        echo -e "${YELLOW}Cancelled.${NC}"
        return
    fi
    
    chart_name=$(echo "$chart_version" | cut -d'/' -f1)
    chart_ver=$(echo "$chart_version" | cut -d'/' -f2)
    
    echo -e "${YELLOW}Downloading $chart_name version $chart_ver...${NC}"
    curl -o "${chart_name}-${chart_ver}.tgz" "$CHARTMUSEUM_URL/charts/${chart_name}-${chart_ver}.tgz"
    
    if [ -f "${chart_name}-${chart_ver}.tgz" ]; then
        echo -e "${GREEN}✓ Downloaded to: ${chart_name}-${chart_ver}.tgz${NC}"
    else
        echo -e "${RED}✗ Failed to download chart${NC}"
    fi
    echo ""
}

# Function to delete a chart version
delete_chart() {
    echo -e "${RED}⚠️  DELETE CHART ⚠️${NC}"
    echo -e "${YELLOW}Available charts:${NC}"
    list_charts
    
    echo -e "\n${YELLOW}Enter chart name and version to delete (format: chartname/version):${NC}"
    read -p "> " chart_version
    
    if [ -z "$chart_version" ]; then
        echo -e "${YELLOW}Cancelled.${NC}"
        return
    fi
    
    chart_name=$(echo "$chart_version" | cut -d'/' -f1)
    chart_ver=$(echo "$chart_version" | cut -d'/' -f2)
    
    echo -e "${RED}Are you sure you want to delete $chart_name version $chart_ver? (y/N):${NC}"
    read -p "> " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        response=$(curl -s -X DELETE "$CHARTMUSEUM_URL/api/charts/$chart_name/$chart_ver")
        echo -e "${GREEN}✓ Chart deleted (if it existed)${NC}"
    else
        echo -e "${YELLOW}Deletion cancelled.${NC}"
    fi
    echo ""
}

# Function to check repository health
check_health() {
    echo -e "${BLUE}🏥 Checking ChartMuseum Health...${NC}\n"
    
    health=$(curl -s "$CHARTMUSEUM_URL/health")
    if echo "$health" | grep -q "healthy"; then
        echo -e "${GREEN}✓ ChartMuseum is healthy${NC}"
        echo -e "${GREEN}✓ API is accessible${NC}"
        echo -e "${GREEN}✓ Storage is working${NC}"
    else
        echo -e "${RED}✗ ChartMuseum is not healthy${NC}"
    fi
    echo ""
}

# Function to show statistics
show_stats() {
    echo -e "${BLUE}📊 Repository Statistics${NC}\n"
    
    charts=$(curl -s "$CHARTMUSEUM_URL/api/charts")
    chart_count=$(echo "$charts" | jq 'length' 2>/dev/null || echo "0")
    total_versions=$(echo "$charts" | jq '[.[] | length] | add' 2>/dev/null || echo "0")
    
    echo -e "${GREEN}Total Charts:${NC} $chart_count"
    echo -e "${GREEN}Total Versions:${NC} $total_versions"
    echo ""
    
    echo -e "${CYAN}Chart List:${NC}"
    echo "$charts" | jq -r 'to_entries[] | "  - \(.key): \(.value | length) version(s)"' 2>/dev/null || echo "  No charts found"
    echo ""
}

# Function to add Helm repo locally
add_helm_repo() {
    echo -e "${BLUE}🔗 Adding to Local Helm...${NC}"
    helm repo add my-charts "$CHARTMUSEUM_URL" --force-update
    helm repo update
    echo -e "${GREEN}✓ Repository added as 'my-charts'${NC}"
    echo -e "${GREEN}✓ Run 'helm search repo my-charts/' to see charts${NC}"
    echo ""
}

# Main menu
while true; do
    show_header
    
    echo -e "${CYAN}Select an option:${NC}"
    echo -e "  ${GREEN}1)${NC} 📋 List all charts"
    echo -e "  ${GREEN}2)${NC} 🔍 Show chart details"
    echo -e "  ${GREEN}3)${NC} 📤 Push a chart"
    echo -e "  ${GREEN}4)${NC} 📥 Download a chart"
    echo -e "  ${GREEN}5)${NC} 🏥 Check health"
    echo -e "  ${GREEN}6)${NC} 📊 Show statistics"
    echo -e "  ${GREEN}7)${NC} 🔗 Add to local Helm"
    echo -e "  ${GREEN}8)${NC} 🗑️  Delete a chart version"
    echo -e "  ${GREEN}9)${NC} 🔄 Refresh/Reload"
    echo -e "  ${RED}0)${NC} 🚪 Exit"
    echo ""
    read -p "Enter your choice (0-9): " choice
    
    case $choice in
        1) list_charts ;;
        2) 
            echo -e "${YELLOW}Enter chart name:${NC}"
            read -p "> " chart_name
            show_chart_details "$chart_name"
            ;;
        3) push_chart ;;
        4) download_chart ;;
        5) check_health ;;
        6) show_stats ;;
        7) add_helm_repo ;;
        8) delete_chart ;;
        9) continue ;;
        0) 
            echo -e "${GREEN}Goodbye! 👋${NC}"
            exit 0
            ;;
        *) 
            echo -e "${RED}Invalid option. Press Enter to continue...${NC}"
            read
            ;;
    esac
    
    if [ "$choice" != "9" ]; then
        echo -e "${YELLOW}Press Enter to continue...${NC}"
        read
    fi
done
EOF

# Make the script executable
chmod +x ~/personal_repo/devops-tool/chartmuseum-interactive.sh