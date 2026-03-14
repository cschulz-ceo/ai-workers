#!/bin/bash
# test-queue-integration.sh - Comprehensive n8n queue mode testing
# Tests all aspects of n8n queue mode implementation
# Usage: bash scripts/test/test-queue-integration.sh [option]

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
N8N_URL="http://localhost:5678"
REDIS_HOST="localhost"
REDIS_PORT="6379"
POSTGRES_HOST="localhost"
POSTGRES_PORT="5432"
TEST_CHANNEL="#test-ai-workers"

log() {
    echo -e "${NC}[$(date +%H:%M:%S)]${NC} $*"
}

success() {
    echo -e "${GREEN}✅ $*${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $*${NC}"
}

error() {
    echo -e "${RED}❌ $*${NC}"
}

header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Test Redis connectivity and functionality
test_redis_connectivity() {
    header "Testing Redis Connectivity"
    
    # Test basic connectivity
    log "Testing Redis ping..."
    if docker exec n8n-redis redis-cli ping > /dev/null 2>&1; then
        success "Redis ping: OK"
    else
        error "Redis ping: FAILED"
        return 1
    fi
    
    # Test Redis memory usage
    log "Checking Redis memory usage..."
    local redis_memory=$(docker exec n8n-redis redis-cli info memory | grep "used_memory:" | cut -d: -f2)
    if [ -n "$redis_memory" ]; then
        success "Redis memory used: ${redis_memory} bytes"
    else
        warning "Could not retrieve Redis memory usage"
    fi
    
    # Test Redis queue depth
    log "Checking queue depth..."
    local queue_depth=$(docker exec n8n-redis redis-cli llen n8n:queue 2>/dev/null || echo "0")
    success "Current queue depth: $queue_depth"
    
    return 0
}

# Test PostgreSQL connectivity and functionality
test_postgres_connectivity() {
    header "Testing PostgreSQL Connectivity"
    
    # Test basic connectivity
    log "Testing PostgreSQL connection..."
    if PGPASSWORD=${POSTGRES_PASSWORD} docker exec n8n-postgres psql -U n8n -d n8n_queue -c "SELECT 1;" > /dev/null 2>&1; then
        success "PostgreSQL connection: OK"
    else
        error "PostgreSQL connection: FAILED"
        return 1
    fi
    
    # Test database size
    log "Checking database size..."
    local db_size=$(PGPASSWORD=${POSTGRES_PASSWORD} docker exec n8n-postgres psql -U n8n -d n8n_queue -c "SELECT pg_size_pretty(pg_database_size('n8n_queue'));" 2>/dev/null || echo "Unknown")
    if [ "$db_size" != "Unknown" ]; then
        success "Database size: $db_size"
    else
        warning "Could not retrieve database size"
    fi
    
    # Test connection count
    log "Checking active connections..."
    local conn_count=$(PGPASSWORD=${POSTGRES_PASSWORD} docker exec n8n-postgres psql -U n8n -d n8n_queue -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';" 2>/dev/null || echo "0")
    success "Active connections: $conn_count"
    
    return 0
}

# Test n8n queue mode functionality
test_n8n_queue_mode() {
    header "Testing n8n Queue Mode"
    
    # Test n8n health
    log "Testing n8n health endpoint..."
    local health_response=$(curl -s "$N8N_URL/healthz" 2>/dev/null || echo '{"status":"error"}')
    local health_status=$(echo "$health_response" | jq -r '.status // "error"')
    
    if [ "$health_status" = "ok" ]; then
        success "n8n health: OK"
    else
        error "n8n health: FAILED ($health_status)"
        return 1
    fi
    
    # Test execution mode
    log "Checking execution mode..."
    local execution_mode=$(echo "$health_response" | jq -r '.execution_mode // "main"')
    if [ "$execution_mode" = "queue" ]; then
        success "Execution mode: queue"
    else
        error "Execution mode: $execution_mode (expected: queue)"
        return 1
    fi
    
    # Test worker configuration
    log "Checking worker configuration..."
    local worker_count=$(echo "$health_response" | jq -r '.concurrency_limit // 1')
    if [ "$worker_count" -ge 4 ]; then
        success "Workers configured: $worker_count"
    else
        warning "Workers configured: $worker_count (expected: 4+)"
    fi
    
    return 0
}

# Test concurrent workflow execution
test_concurrent_workflows() {
    header "Testing Concurrent Workflow Execution"
    
    log "Starting 4 concurrent workflow tests..."
    local start_time=$(date +%s)
    
    # Launch 4 workflows in background
    for i in {1..4}; do
        curl -s -X POST "$N8N_URL/webhook/slack-command" \
            -H "Content-Type: application/json" \
            -d "{\"text\": \"/ai kevin: concurrent test $i\", \"channel\": \"$TEST_CHANNEL\"}" \
            > /tmp/test_$i.log 2>&1 &
        
        # Small delay between requests
        sleep 0.5
    done
    
    # Wait for all to complete
    log "Waiting for workflows to complete..."
    wait
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Check results
    local success_count=0
    local error_count=0
    
    for i in {1..4}; do
        if [ -f "/tmp/test_$i.log" ]; then
            if grep -q "success\|completed" "/tmp/test_$i.log"; then
                success_count=$((success_count + 1))
            else
                error_count=$((error_count + 1))
            fi
        fi
    done
    
    success "Concurrent test completed in ${duration}s"
    success "Successful workflows: $success_count/4"
    success "Failed workflows: $error_count/4"
    
    # Cleanup
    rm -f /tmp/test_*.log
    
    return 0
}

# Test queue behavior under load
test_queue_behavior() {
    header "Testing Queue Behavior Under Load"
    
    log "Testing queue depth under load..."
    
    # Get initial queue depth
    local initial_depth=$(docker exec n8n-redis redis-cli llen n8n:queue 2>/dev/null || echo "0")
    success "Initial queue depth: $initial_depth"
    
    # Submit 10 rapid requests
    log "Submitting 10 rapid requests..."
    for i in {1..10}; do
        curl -s -X POST "$N8N_URL/webhook/slack-command" \
            -H "Content-Type: application/json" \
            -d "{\"text\": \"/ai kevin: load test $i\", \"channel\": \"$TEST_CHANNEL\"}" \
            > /dev/null 2>&1 &
        
        if [ $((i % 3)) -eq 0 ]; then
            sleep 0.1  # Brief pause every 3 requests
        fi
    done
    
    # Wait for processing
    sleep 5
    
    # Check queue depth after load
    local peak_depth=$(docker exec n8n-redis redis-cli llen n8n:queue 2>/dev/null || echo "0")
    success "Peak queue depth: $peak_depth"
    
    # Wait for queue to clear
    log "Waiting for queue to clear..."
    local wait_time=0
    while [ $wait_time -lt 60 ]; do
        current_depth=$(docker exec n8n-redis redis-cli llen n8n:queue 2>/dev/null || echo "0")
        if [ "$current_depth" -eq 0 ]; then
            success "Queue cleared after ${wait_time}s"
            break
        fi
        sleep 2
        wait_time=$((wait_time + 2))
    done
    
    if [ $wait_time -ge 60 ]; then
        warning "Queue did not clear within 60 seconds (depth: $current_depth)"
    fi
    
    return 0
}

# Test timeout handling
test_timeout_handling() {
    header "Testing Timeout Handling"
    
    log "Testing long-running request with 600s timeout..."
    local start_time=$(date +%s)
    
    # Submit a long-running request
    timeout 610s curl -s -X POST "$N8N_URL/webhook/slack-command" \
        -H "Content-Type: application/json" \
        -d "{\"text\": \"/ai kevin: Explain microservices architecture in detail with examples and best practices for production systems including service discovery, load balancing, data consistency patterns, monitoring strategies, and deployment approaches.\", \"channel\": \"$TEST_CHANNEL\"}" \
        -o /tmp/timeout_test.log 2>&1
    
    local exit_code=$?
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [ $exit_code -eq 124 ]; then
        error "Request timed out after ${duration}s (curl timeout)"
        return 1
    elif [ $exit_code -eq 0 ]; then
        success "Long request completed in ${duration}s"
        
        # Check if response contains completion indicators
        if grep -q "completed\|success\|finished" /tmp/timeout_test.log; then
            success "Response indicates successful completion"
        else
            warning "Response may be incomplete"
        fi
    else
        error "Request failed with exit code: $exit_code"
        return 1
    fi
    
    # Cleanup
    rm -f /tmp/timeout_test.log
    
    return 0
}

# Test metrics collection
test_metrics_collection() {
    header "Testing Metrics Collection"
    
    log "Testing metrics endpoint..."
    local metrics_response=$(curl -s http://localhost:9201/metrics 2>/dev/null || echo "# ERROR")
    
    if echo "$metrics_response" | grep -q "n8n_queue_depth"; then
        success "Queue depth metrics: OK"
    else
        error "Queue depth metrics: FAILED"
        return 1
    fi
    
    if echo "$metrics_response" | grep -q "n8n_active_workers"; then
        success "Worker metrics: OK"
    else
        error "Worker metrics: FAILED"
        return 1
    fi
    
    if echo "$metrics_response" | grep -q "n8n_system_health"; then
        success "System health metrics: OK"
    else
        error "System health metrics: FAILED"
        return 1
    fi
    
    if echo "$metrics_response" | grep -q "ollama_response_time"; then
        success "Ollama metrics: OK"
    else
        error "Ollama metrics: FAILED"
        return 1
    fi
    
    local metrics_count=$(echo "$metrics_response" | grep -c "^n8n_" | wc -l)
    success "Total n8n metrics collected: $metrics_count"
    
    return 0
}

# Test load balancing across workers
test_load_balancing() {
    header "Testing Load Balancing"
    
    log "Testing load distribution across workers..."
    
    # Submit requests with different complexity levels
    local requests=(
        "/ai kevin: simple test"
        "/ai jason: medium complexity function"
        "/ai scaachi: creative writing task"
        "/ai christian: business strategy analysis"
    )
    
    for i in "${!requests[@]}"; do
        log "Submitting request: $i"
        curl -s -X POST "$N8N_URL/webhook/slack-command" \
            -H "Content-Type: application/json" \
            -d "{\"text\": \"$i\", \"channel\": \"$TEST_CHANNEL\"}" \
            > /tmp/load_balance_$i.log 2>&1 &
        
        sleep 1  # Stagger requests
    done
    
    # Wait for completion
    wait
    
    # Analyze distribution
    local completed=0
    for i in "${!requests[@]}"; do
        if [ -f "/tmp/load_balance_$i.log" ]; then
            if grep -q "success\|completed" "/tmp/load_balance_$i.log"; then
                completed=$((completed + 1))
            fi
        fi
    done
    
    success "Load balancing test completed"
    success "Requests completed: $completed/${#requests[@]}"
    
    # Cleanup
    rm -f /tmp/load_balance_*.log
    
    return 0
}

# Performance benchmark
test_performance_benchmark() {
    header "Performance Benchmark"
    
    log "Running performance benchmark..."
    
    local total_requests=20
    local start_time=$(date +%s)
    local success_count=0
    
    # Submit requests sequentially
    for i in $(seq 1 $total_requests); do
        curl -s -X POST "$N8N_URL/webhook/slack-command" \
            -H "Content-Type: application/json" \
            -d "{\"text\": \"/ai kevin: benchmark request $i\", \"channel\": \"$TEST_CHANNEL\"}" \
            > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            success_count=$((success_count + 1))
        fi
        
        # Small delay between requests
        sleep 0.2
    done
    
    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    local avg_time=$((total_time / total_requests))
    local throughput=$((success_count * 60 / total_time))
    
    success "Benchmark completed"
    success "Total requests: $total_requests"
    success "Successful requests: $success_count"
    success "Total time: ${total_time}s"
    success "Average time per request: ${avg_time}s"
    success "Throughput: ${throughput} req/min"
    
    return 0
}

# Show system status
show_system_status() {
    header "Current System Status"
    
    echo ""
    log "Docker containers:"
    docker-compose -f /home/biulatech/ai-workers-1/configs/queue/docker-compose.yml ps
    
    echo ""
    log "Resource usage:"
    docker stats --no-stream n8n-redis n8n-postgres n8n 2>/dev/null || true
    
    echo ""
    log "Network information:"
    docker network ls | grep "n8n-network"
    
    echo ""
    log "Service endpoints:"
    echo "n8n: $N8N_URL"
    echo "Redis: $REDIS_HOST:$REDIS_PORT"
    echo "PostgreSQL: $POSTGRES_HOST:$POSTGRES_PORT"
    echo "Metrics: http://localhost:9201/metrics"
}

# Help and usage
show_help() {
    echo "n8n Queue Integration Test Suite"
    echo ""
    echo "Usage: $0 [option]"
    echo ""
    echo "Options:"
    echo "  redis          Test Redis connectivity and functionality"
    echo "  postgres        Test PostgreSQL connectivity and functionality"
    echo "  n8n            Test n8n queue mode functionality"
    echo "  concurrent     Test concurrent workflow execution"
    echo "  queue          Test queue behavior under load"
    echo "  timeout         Test timeout handling"
    echo "  metrics         Test metrics collection"
    echo "  load-balance    Test load balancing across workers"
    echo "  benchmark       Performance benchmark test"
    echo "  status          Show current system status"
    echo "  all            Run all tests"
    echo ""
    echo "Examples:"
    echo "  $0 redis         # Test Redis connectivity"
    echo "  $0 all            # Run complete test suite"
}

# Main execution
main() {
    case "${1:-}" in
        "redis")
            test_redis_connectivity
            ;;
        "postgres")
            test_postgres_connectivity
            ;;
        "n8n")
            test_n8n_queue_mode
            ;;
        "concurrent")
            test_concurrent_workflows
            ;;
        "queue")
            test_queue_behavior
            ;;
        "timeout")
            test_timeout_handling
            ;;
        "metrics")
            test_metrics_collection
            ;;
        "load-balance")
            test_load_balancing
            ;;
        "benchmark")
            test_performance_benchmark
            ;;
        "status")
            show_system_status
            ;;
        "all")
            header "Running Complete Test Suite"
            test_redis_connectivity || exit 1
            test_postgres_connectivity || exit 1
            test_n8n_queue_mode || exit 1
            test_concurrent_workflows || exit 1
            test_queue_behavior || exit 1
            test_timeout_handling || exit 1
            test_metrics_collection || exit 1
            test_load_balancing || exit 1
            test_performance_benchmark || exit 1
            success "All tests completed!"
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
