# Stack Subscription Service

## Overview
A lightweight subscription management service for handling stack-based notifications and events.

## Features
- Event-driven subscription handling
- Real-time notification system
- Validation middleware
- Subscriber management
- Configurable event dispatching

## Installation

```bash
git clone https://github.com/username/stack-subscribe.git
cd stack-subscribe
dotnet restore
```

## Quick Start

````csharp
// Example usage
var subscriptionService = new SubscriptionService();
await subscriptionService.Subscribe(subscriber);
````

## Configuration
Create `appsettings.json`:

````json
{
  "SubscriptionSettings": {
    "RetryAttempts": 3,
    "TimeoutSeconds": 30,
    "MaxSubscribers": 1000
  }
}
````

## API Reference

### Endpoints
- `POST /api/subscriptions` - Create subscription
- `GET /api/subscriptions` - List subscriptions
- `DELETE /api/subscriptions/{id}` - Remove subscription

## Testing
Run tests using:
```bash
dotnet test
```

## Contributing
1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'feat: Add amazing feature'`)
4. Push branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

