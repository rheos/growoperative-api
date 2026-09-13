# Rails Backend - Food Distribution Platform

A Rails backend system supporting a local food distribution network with an integrated mutual credit payment system.

## Features

- **User Management** - Authentication and user relationships
- **Item Inventory System** - Product listings and inventory management  
- **Item Request System** - Request and fulfillment workflow
- **Order Management** - Order processing and tracking
- **Mutual Credit System** - Community-driven payments using trustlines

## Quick Start

### Prerequisites

- Ruby 3.2.11
- PostgreSQL 16

### Setup

1. Install dependencies:
   ```bash
   bundle update
   bundle install
   ```

2. Configure database:
   - Update username/password in `config/database.yml`

3. Setup database:
   ```bash
   rake db:setup
   ```

4. Start server:
   ```bash
   rails s
   ```

## Documentation

📚 **[Complete Documentation](./doc/README.md)** - Full system documentation

### Key Documentation

- **[Mutual Credit System](./doc/mutual_credit/README.md)** - Community payment system
- **[API Reference](./doc/mutual_credit/api_reference.md)** - Complete API documentation
- **[Database Schema](./doc/mutual_credit/database_schema.md)** - Database structure
- **[Payment Flows](./doc/mutual_credit/payment_flows.md)** - How payments work

## System Overview

This backend powers a local food distribution platform where:

1. **Producers** list available items in inventory
2. **Retailers** can request items from producers  
3. **Consumers** can request items from retailers
4. **Payments** flow through a mutual credit network using trustlines
5. **Orders** track the fulfillment process

## Mutual Credit System

The platform includes a sophisticated mutual credit system that enables:

- **Trustlines** - Bidirectional credit relationships between users
- **Direct Payments** - Between users with established trustlines
- **Multi-hop Payments** - Routed through intermediate users
- **Item Integration** - Automatic payments when accepting item requests
- **Full Audit Trail** - Complete transaction history

See the [Mutual Credit Documentation](./doc/mutual_credit/README.md) for detailed information.

## Contributing

See the [documentation](./doc/README.md) for development guidelines and system architecture.

## License

[License information]
