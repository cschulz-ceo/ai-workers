# N8N Workflow Queue Optimization Guide

**Optimize n8n workflow execution and Ollama model loading to prevent queue buildup and reduce timeout issues.**

## Current Architecture Analysis

### **Current Setup**
- **n8n Worker Limit**: Default (1 worker per execution)
- **Ollama Configuration**: 600s timeout, 10 max queue
- **Issue**: Multiple concurrent requests can queue up Ollama jobs

### **Problem Identified**
- **Queue Buildup**: When multiple Slack commands arrive simultaneously, Ollama jobs queue up
- **Resource Contention**: Queued jobs compete for GPU VRAM
- **Increased Latency**: Later jobs wait for earlier jobs to complete
- **Timeout Risk**: Long-running jobs may exceed 600s timeout due to queue delays

## Optimization Strategies

### **Strategy 1: Workflow Concurrency Control**

#### **n8n Worker Scaling**
```yaml
# docker-compose.yml
services:
  n8n:
    environment:
      - EXECUTIONS_DATA=save
      - EXECUTIONS_PROCESS=main
      - N8N_CONCURRENCY_LIMIT=4  # Increase from default 1
      - N8N_MAX_EXECUTION_TIMEOUT=600  # 10 minutes per workflow
```

#### **Benefits**
- **Parallel Processing**: 4 concurrent workflows vs 1
- **Reduced Queue Times**: Jobs start faster
- **Better Resource Utilization**: More efficient GPU usage

### **Strategy 2: Ollama Model Management**

#### **Model Loading Optimization**
```bash
# Pre-load frequently used models
ollama pull kevin
ollama pull jason
ollama pull scaachi

# Keep models warm (reduces first-request latency)
Environment="OLLAMA_KEEP_ALIVE=30m"  # Keep models in memory longer
```

#### **Benefits**
- **Faster Cold Starts**: Models already loaded
- **Reduced Loading Time**: No need to load per request
- **Better User Experience**: Immediate responses for warm models

### **Strategy 3: Smart Queue Management**

#### **Request Prioritization**
```javascript
// In workflow node before Ollama call
const priorities = {
  'kevin': 1,    // High priority - systems architecture
  'jason': 2,    // High priority - coding tasks
  'scaachi': 3,   // Medium priority - content generation
  'christian': 3,  // Medium priority - prototyping
  'chidi': 2     // High priority - research tasks
};

// Add priority to request metadata
const requestMetadata = {
  priority: priorities[agent] || 5,
  timestamp: Date.now()
};

// Route to priority queue if available
```

#### **Implementation**
- **Priority Queues**: Separate queues for different priority levels
- **Request Throttling**: Limit concurrent low-priority requests
- **Queue Monitoring**: Track queue depth and processing times

### **Strategy 4: Timeout Handling**

#### **Progressive Timeouts**
```json
{
  "timeouts": {
    "quick": 120,      // 2 minutes for simple requests
    "standard": 300,    // 5 minutes for normal requests  
    "complex": 600      // 10 minutes for complex requests
  }
}
```

#### **Dynamic Timeout Selection**
```javascript
// Estimate request complexity
function estimateTimeout(prompt, agent) {
  const complexity = prompt.length + agent.length;
  if (complexity < 100) return "quick";
  if (complexity < 500) return "standard";
  return "complex";
}
```

### **Strategy 5: Monitoring & Alerting**

#### **Queue Metrics**
```yaml
# Prometheus metrics
- job_queue_depth
- job_processing_time
- job_wait_time
- ollama_gpu_utilization
- concurrent_jobs_count
```

#### **Alerting Rules**
- Queue depth > 5: Warning
- Average wait time > 60s: Critical alert
- Ollama GPU utilization > 90%: Warning

## Implementation Plan

### **Phase 1: n8n Configuration**
1. Update `docker-compose.yml` with concurrency settings
2. Add environment variables for timeout management
3. Restart n8n service

### **Phase 2: Ollama Optimization**
1. Configure model pre-loading strategy
2. Adjust keep-alive settings based on usage patterns
3. Implement model priority loading

### **Phase 3: Workflow Updates**
1. Add priority-based routing to key workflows
2. Implement dynamic timeout selection
3. Add queue monitoring and alerting

### **Phase 4: Monitoring Setup**
1. Configure Prometheus metrics for queue depth
2. Set up Grafana dashboard for queue visualization
3. Configure alerting thresholds

## Expected Outcomes

### **Performance Improvements**
- **50% reduction** in average response times
- **Zero queue overflows** with proper concurrency control
- **Better resource utilization** with smart model management
- **Improved reliability** with progressive timeout handling

### **User Experience**
- **Faster responses** for frequently used agents (pre-loaded models)
- **Consistent performance** regardless of system load
- **Better error handling** with clear timeout messages

### **System Stability**
- **No resource exhaustion** from queue buildup
- **Predictable performance** under load
- **Scalable architecture** supporting increased usage

## Configuration Files

### **docker-compose.yml Updates**
```yaml
services:
  n8n:
    environment:
      - N8N_CONCURRENCY_LIMIT=4
      - N8N_MAX_EXECUTION_TIMEOUT=600
      - EXECUTIONS_DATA=save
      - EXECUTIONS_PROCESS=main
```

### **Environment Variables**
```bash
# n8n settings
export N8N_CONCURRENCY_LIMIT=4
export N8N_MAX_EXECUTION_TIMEOUT=600

# Ollama settings
export OLLAMA_KEEP_ALIVE=30m
export OLLAMA_REQUEST_TIMEOUT=600
export OLLAMA_MAX_QUEUE=20
```

## Monitoring Setup

### **Prometheus Configuration**
```yaml
# prometheus.yml additions
- job_name: n8n_queue_depth
  scrape_interval: 15s
  metrics_path: /metrics
  static_configs:
    - targets:
      - job_name: n8n_queue_depth
        - target: ['localhost:5678']
```

### **Grafana Dashboard**
- Queue depth visualization
- Processing time trends
- Resource utilization charts
- Alert status panel

---

**Implementation of these optimizations will significantly improve workflow performance, reduce timeout issues, and provide better user experience under load.**
