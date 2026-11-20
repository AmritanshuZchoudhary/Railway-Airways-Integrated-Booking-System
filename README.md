# 🚆 Railway Reservation and Airways Management System

A database-driven Railway Reservation Management System designed to simplify train reservations, passenger management, ticket booking, and waitlist handling.

The project uses **MySQL, SQL triggers, stored procedures, and a web-based interface** to demonstrate real-world database management concepts.

One of its key features is an automated waitlist promotion mechanism combined with a historical-data-based probability estimation system that helps passengers understand their chances of getting a confirmed seat.

---

## 📌 Project Overview

Traditional railway reservation systems manage ticket bookings, cancellations, and waiting lists. However, passengers often have limited information about their chances of getting a confirmed ticket when they are placed on a waiting list.

Our system addresses this problem by introducing:

* Automated waitlist management.
* Automatic promotion of waitlisted passengers when confirmed tickets become available.
* Probability-based confirmation estimation using historical booking data.
* Centralized management of trains, passengers, bookings, and reservations.
* A separate **Airways booking module** with expanded airport and flight coverage, dynamic fares, controlled overbooking with a priority standby list, historical standby confirmation estimates, baggage fees and an aircraft-conflict check, linked through the shared passenger account and loyalty points.

The primary objective is to demonstrate how database concepts can be applied to a combined railway reservation and airline booking prototype.

---

## ✨ Key Features

### 1. User and Passenger Management

* Passenger registration and management.
* Storage of passenger details.
* Management of booking information.

### 2. Train Management

* Train information management.
* Train schedules and route details.
* Seat availability management.

### 3. Ticket Reservation

* Book railway tickets.
* Generate booking records.
* Maintain reservation details.
* Track booking status.

### 4. Automated Waitlist Management

* Passengers are automatically added to the waiting list when confirmed seats are unavailable.
* Each waitlisted passenger receives a waiting-list position.
* When a confirmed booking is cancelled, the database trigger automatically promotes the next eligible passenger.
* The booking status is updated automatically.

### 5. Waitlist Confirmation Probability

An additional feature that estimates the probability of a waitlisted passenger receiving a confirmed seat.

* Uses historical booking and cancellation records.
* Analyzes previous waitlist confirmation outcomes.
* Provides an estimated confirmation probability.
* Helps passengers make more informed booking decisions.

**Note:** The probability is an estimate based on historical data and is not a guarantee of confirmation.

---

### 6. Airline Booking Module

* Direct flights between fictional airports, dated flight schedules, seat maps generated per flight.
* Dynamic fare (occupancy and days to departure), controlled overbooking with a priority standby queue, baggage allowance and excess fee, refund slabs, and an aircraft assignment conflict check.
* See [Airline Module](#️-airline-module-air-booking) below.

### 7. Flight Alternative for Low Waitlist Probability

* When the historical chance of a confirmed train seat is **below 30 %**, the waiting-list card also offers **same-day flights between the same two cities, with a confirmed seat, at about the same price** (within ±25 % of the train fare), bookable in one click.
* Stations and airports are matched by city, so no extra table is needed; the feature switches itself off if the airline module is not installed.
* Worked example (New Delhi to Lucknow: train 90005 at 2,200 with a 12.5 % estimate; flights DS410 at 2,145 and DS412 at 1,950 are suggested, CA411 at 6,240 is not): see [`docs/flight_alternative_demo.md`](docs/flight_alternative_demo.md).

### 8. Shared Loyalty and Trip History

* One loyalty balance and tier (BASIC, SILVER, GOLD) shared across rail and air bookings, with a loyalty ledger and unified trip history. Confirmed fares earn 1 point per ₹100 paid; flight tickets receive tier discounts: BASIC 0%, SILVER 5% (1,000+ points), and GOLD 10% (5,000+ points). The base fare, tier, discount percentage, discount amount, and final amount paid are stored per airline booking.

---

## 🛠️ Technologies Used

| Technology            | Purpose                            |
| --------------------- | ---------------------------------- |
| HTML, CSS, JavaScript | Frontend development               |
| React / Vite          | Frontend framework and development |
| Node.js               | Backend runtime                    |
| Express.js            | Backend API                        |
| MySQL 8.0             | Database management                |
| SQL                   | Database queries and operations    |
| Stored Procedures     | Reusable database operations       |
| SQL Triggers          | Automated waitlist management      |
| Git & GitHub          | Version control and collaboration  |

---

## 📂 Project Structure

```text
Railway-Reservation-System/
│
├── backend/
│   └── src/
│       ├── controllers/   (railway + airController, airAdminController, loyaltyController)
│       ├── middleware/
│       ├── routes/        (railway + airRoutes, loyaltyRoutes)
│       ├── services/
│       └── index.js
│
├── frontend/
│   └── src/
│       ├── components/
│       ├── pages/         (PassengerDashboard, AirDashboard, Login, Register)
│       ├── services/
│       ├── App.jsx
│       └── main.jsx
│
├── database/
│   ├── 01_schema.sql
│   ├── 02_constraints_and_indexes.sql
│   ├── 03_stored_procedures.sql
│   ├── 04_triggers.sql
│   ├── 05_views_and_reports.sql
│   ├── 06_seed_data.sql
│   ├── 07_probability_history.sql
│   ├── 08_dcl_permissions.sql
│   ├── 09_air_schema.sql              (airline_db tables)
│   ├── 10_core_loyalty.sql            (transport_core: loyalty ledger, trip history, users.loyalty_points/tier)
│   ├── 11_air_procedures.sql          (fares, refunds, booking, cancellation, baggage, aircraft check)
│   ├── 12_air_triggers.sql            (seat generation, standby promotion, history, baggage fee, aircraft conflict)
│   ├── 13_air_views_and_reports.sql
│   ├── 14_air_seed_data.sql
│   ├── 15_air_dcl_permissions.sql     (roles: rail_admin, air_admin, passenger_user)
│   ├── 20_air_probability_history.sql (synthetic airline standby history)
│   ├── 21_air_probability_procedures.sql (finalize completed standby outcomes)
│   ├── 22_expand_rail_routes_30_days.sql  (two daily direct demo train options per station pair)
│   ├── 23_expand_air_routes_30_days.sql   (two daily direct demo flight options per airport pair)
│   ├── 24_air_loyalty_flight_discounts.sql (tier-based flight fare discounts and persisted fare breakdown)
│   ├── 16_demo_railway_one_seat.sql   (optional: one-seat railway waitlist demo)
│   ├── 17_demo_airline_one_seat.sql   (optional: one-seat airline standby demo)
│   ├── 18_demo_low_probability_railway.sql   (example: train with a 12.5 % waitlist estimate)
│   └── 19_demo_low_probability_airline.sql   (example: same-day flights at about the train fare)
│
├── docs/
│   ├── flight_alternative_demo.md
│   ├── flight_loyalty_discount_demo.md
│   └── viva_guide_and_project_report.md
│
├── README.md
└── .gitignore
```

---

## 🗄️ Database Implementation

The project uses MySQL as its relational database management system.

The database is responsible for maintaining relationships between passengers, trains, reservations, bookings, and waitlist records.

### Important Database Concepts Implemented

**1. Primary Keys and Foreign Keys**

* Maintain relationships between different tables.
* Ensure referential integrity.

**2. Constraints**

* Maintain data accuracy.
* Prevent invalid database entries.

**3. Stored Procedures**

* Implement reusable database operations.
* Simplify booking and reservation-related operations.

**4. Triggers**

* Automate database operations.
* Handle waitlist promotion after ticket cancellation.

**5. Views**

* Simplify access to frequently required information.
* Generate useful booking and reservation reports.

**6. Indexes**

* Improve query performance.
* Optimize database searching operations.

---

## ⚙️ How the Waitlist System Works

The automated waitlist mechanism follows this process:

1. A passenger requests a ticket.
2. If a confirmed seat is available, the booking is confirmed.
3. If no confirmed seat is available, the passenger is added to the waiting list.
4. When a confirmed ticket is cancelled, a database trigger is activated.
5. The trigger identifies the next eligible passenger in the waiting list.
6. The passenger's booking status is updated.
7. The available seat is assigned according to the waitlist order.

This process reduces the need for manual waitlist management.

---

## 📊 Probability-Based Confirmation Estimation

The system introduces a historical-data-based approach to estimate waitlist confirmation chances.

It uses previously recorded booking, cancellation, and waitlist outcomes to calculate an estimated probability.

The purpose is to provide passengers with additional information about their waiting-list status.

Unlike a traditional waitlist system, this feature introduces a predictive element into the reservation process.

---

## ✈️ Airline Module (Air Booking)

The airline module follows the project plan in the project report (Part II, "Airline Management System") and keeps the two modules separate:

| Plan name | MySQL database | Contents |
|---|---|---|
| rail | `railway_db` | The original railway tables (unchanged) and the shared passenger account `users` |
| air | `airline_db` | `airlines`, `airports`, `aircraft`, `flights`, `fare_rules`, `flight_schedules`, `flight_seats`, `air_bookings`, `air_seat_allocations`, `air_standby_entries`, `air_cancellations`, `air_booking_history`, `air_waitlist_probability_history`, `baggage` |
| core | `transport_core` | `loyalty_txn` (loyalty ledger) and the view `v_trip_history`; the passenger itself stays in `railway_db.users` |

The railway tables never reference airline tables and the airline tables never reference railway tables. The only links are `air_bookings.passenger_id -> railway_db.users` and the loyalty ledger.

### Novelties implemented

| ID | Feature | Where |
|---|---|---|
| A1 | Dynamic fare: base fare x occupancy factor (1 + 0.5 x occupied / total seats) x 1.3 when the flight is under 7 days away | `fn_air_fare` |
| A2 | Controlled overbooking with priority standby: when seats are full, up to `overbook_limit` extra bookings join STANDBY, ordered by loyalty tier (GOLD, SILVER, BASIC) then booking time; a cancellation promotes the first one automatically | `sp_air_create_booking`, trigger `trg_air_promote_standby_after_cancellation` |
| A3 | Baggage: 15 kg (economy) or 30 kg (business) free per booking, 400 rupees per extra kg | trigger `trg_air_baggage_before_insert` |
| A4 | Aircraft conflict check: an aircraft cannot fly overlapping schedules (45-minute turnaround) and must belong to the flight's airline | `sp_air_assert_aircraft_free`, triggers on `flight_schedules` |
| S1 | Loyalty: 1 point per 100 rupees of a confirmed fare (rail or air), reversed on cancellation; tier is a generated column (SILVER from 1000, GOLD from 5000 points) | `transport_core.sp_award_loyalty`, triggers on `bookings` and `air_bookings` |
| S2 | Loyalty ledger with an exclusive arc: each row refers to exactly one rail or one air booking | CHECK constraint on `loyalty_txn` |
| S3 | Unified trip history for rail and air | view `transport_core.v_trip_history` |
| S4 | Role separation | `15_air_dcl_permissions.sql` |
| - | Refund slabs by time before departure (over 48 h: 90 %, 12 to 48 h: 50 %, under 12 h: 0 %; standby bookings refunded in full) | `fn_air_refund` |

The railway novelties R2 (refund slabs), R3 (waitlist expiry job) and R4 (distance-based fare) from the plan are **not** implemented in the railway module yet.

### Design notes and differences from the report

* One booking is one passenger, as in the railway module.
* The standby position is derived (ranked by the view `vw_air_booking_overview`) instead of stored, because a higher-tier passenger joining later changes everyone's position.
* Released seat allocations are deleted (same convention as the railway module); `air_booking_history` and `air_cancellations` keep the audit trail.
* Seat maps are generated by a trigger from the aircraft's seat counts when a schedule is created.
* All airlines, airports and flights are fictional demonstration data.

### API

| Method and path | Purpose |
|---|---|
| `GET /api/air/airports` | Airport list |
| `GET /api/air/flights/search` | Search by `origin_airport_id`, `destination_airport_id`, `flight_date`, `cabin_class` |
| `GET /api/air/bookings/my` | The passenger's bookings with seat, standby position and baggage |
| `GET /api/air/bookings/probability?air_booking_id=` | Historical confirmation estimate for the passenger's active standby booking |
| `POST /api/air/admin/finalize-history` | Admin only: saves known outcomes from completed flight standby queues |
| `POST /api/air/bookings/create` | Book (`flight_schedule_id`, `cabin_class`); returns CONFIRMED or STANDBY |
| `POST /api/air/bookings/cancel` | Cancel (`air_booking_id`); returns the refund |
| `POST /api/air/bookings/baggage` | Add a bag (`air_booking_id`, `weight_kg`) |
| `GET /api/probability?booking_id=` | Railway waitlist estimate; when it is below 30 % the response also has `alternatives.flights` (same-day flights within ±25 % of the train fare with a confirmed seat) |
| `GET /api/loyalty/me`, `GET /api/loyalty/trips` | Loyalty balance and ledger, unified trip history |
| `GET /api/air/admin/summary`, `GET /api/air/admin/schedule-options`, `POST /api/air/admin/schedules` | Admin only: totals, and creating a schedule (demonstrates A4) |

In the website, open **Air booking** in the sidebar of the railway dashboard (route `/air`).

### Quick demo

1. Register four or more passengers. Search NDA to MBA three days ahead (schedule 2001 has 4 economy seats and a standby limit of 2).
2. Book with four accounts (CONFIRMED), then with two more (STANDBY); a seventh booking is rejected.
3. Cancel one confirmed booking: the first standby passenger is promoted automatically and the refund follows the time slab.
4. Add a 20 kg bag to a confirmed economy booking: the fee is 400 x 5 kg.
5. As admin, create a schedule for flight DS150 with aircraft VT-DS01 on the same date as DS101: the trigger rejects it; with VT-DS02 it succeeds.

### Two-tab demonstration: waiting list to confirmed

Files `16` and `17` add a train with a single AC seat (train 90004, New Delhi to Jaipur) and a flight with a single economy seat (DS777, New Delhi to Jaipur), both two days from today. They create **no accounts and no tickets**: register two passengers yourself, one per browser tab, book the same journey with both (the first is CONFIRMED, the second is WAITLISTED or on STANDBY), then cancel the first ticket and watch the second tab upgrade to CONFIRMED by itself within a few seconds. Steps and talking points are in [`docs/two_tab_upgrade_demo.md`](docs/two_tab_upgrade_demo.md). Re-run `16` and `17` to move the journey to two days from today and clear its bookings.

For this to work the login is stored **per browser tab** (`sessionStorage`) instead of once per browser, and the dashboards refresh the passenger's tickets every few seconds while the tab is visible. Closing a tab therefore signs it out.

---

## 🚀 Installation and Setup

Follow these steps to run the project locally.

### Prerequisites

Make sure you have installed:

* Node.js
* npm
* MySQL Server 8.0 or later
* Visual Studio Code
* Git

### Step 1: Clone the Repository

```bash
git clone https://github.com/YOUR_USERNAME/Railway-Reservation-System.git
```

Navigate into the project:

```bash
cd Railway-Reservation-System
```

### Step 2: Set Up the Database

1. Open MySQL Workbench or MySQL Command Line.
2. Execute the SQL files inside the `database` folder in the appropriate order.
3. Verify that the database and tables have been created successfully.

Recommended execution order:

1. `01_schema.sql`
2. `02_constraints_and_indexes.sql`
3. `03_stored_procedures.sql`
4. `04_triggers.sql`
5. `05_views_and_reports.sql`
6. `06_seed_data.sql`
7. `22_expand_rail_routes_30_days.sql` (two direct train options for every ordered station pair, daily for 30 days)
8. `07_probability_history.sql` (run after route expansion so new routes also get demo history)
9. `08_dcl_permissions.sql` (optional, mostly commented example)
10. `09_air_schema.sql` (airline module, creates `airline_db`)
11. `10_core_loyalty.sql` (creates `transport_core`, adds `loyalty_points` and `tier` to `railway_db.users`)
12. `11_air_procedures.sql`
13. `12_air_triggers.sql`
14. `13_air_views_and_reports.sql`
15. `14_air_seed_data.sql`
16. `23_expand_air_routes_30_days.sql` (two direct flight options for every ordered airport pair, daily for 30 days)
17. `15_air_dcl_permissions.sql` (creates passwordless roles only)
18. `20_air_probability_history.sql` (run after airport/flight expansion so new routes also get demo history)
19. `21_air_probability_procedures.sql` (finalizes completed airline standby outcomes)
20. `24_air_loyalty_flight_discounts.sql` (adds BASIC 0%, SILVER 5%, GOLD 10% discounts to flight bookings; run after 10 and 11, once airline tables exist)
21. `16_demo_railway_one_seat.sql` (optional: a train with one AC seat for the two-tab waiting-list demonstration)
22. `17_demo_airline_one_seat.sql` (optional: a flight with one economy seat for the same demonstration, needs 09 to 15)
23. `18_demo_low_probability_railway.sql` (optional: train 90005 New Delhi to Lucknow with a low waitlist probability, needs 01 to 08)
24. `19_demo_low_probability_airline.sql` (optional: three New Delhi to Lucknow flights for the flight-alternative example, needs 09 to 20)

Files 09 to 15, 20, 21 and 24 install the Airways module, standby-probability history, and flight loyalty discounts. The 22 and 23 network expansion migrations create two direct demo service options in each direction for every station/airport pair that exists when the migration runs, then add a schedule on each of the next 30 calendar dates (today through today + 29 days). They are idempotent and can be re-run to add schedules to the rolling 30-day window or to cover stations/airports added later. For an already installed database, run only `22_expand_rail_routes_30_days.sql` and `23_expand_air_routes_30_days.sql`; do not re-run the older fixed-ID seed scripts just to extend dates. Re-run `07_probability_history.sql` and `20_air_probability_history.sql` after expansion if you want synthetic probability observations associated with the newly generated routes. The air migration rebuilds the flight-seat generation trigger with a set-based insert so generating the larger schedule set is faster. All sample stations, airports, trains, flights, dates, distances, fares, and probability observations are fictional academic demonstration data, not real-world timetables. See `docs/monthly_route_coverage.md` for coverage verification and the Indore-to-Jaipur test. The 24 migration adds persisted fare-breakdown columns to `air_bookings`, replaces the airline booking procedure to calculate discounts server-side, and refreshes the airline booking/trip-history views. Existing bookings are kept with a 0% legacy discount; new airline bookings use the tier benefit at booking time. Flight discount policy: BASIC (<1,000 points) 0%, SILVER (1,000-4,999) 5%, GOLD (5,000+) 10%. `air_bookings.fare` stores the final discounted fare payable; loyalty points are earned on that net fare. Do not drop your databases unless you intend to erase bookings.

For an already-running installation that has the shared loyalty tables and Airways module, back up `railway_db`, `airline_db`, and `transport_core`, then run only `database/24_air_loyalty_flight_discounts.sql` in MySQL Workbench. Run it after `09_air_schema.sql`, `10_core_loyalty.sql`, `11_air_procedures.sql`, and `12_air_triggers.sql` have been installed. The migration temporarily disables Workbench safe-update mode only for the legacy-fare backfill, then restores the previous setting. Restart the backend after it completes. The passenger Airways search shows base fare, tier discount, money saved, and final fare; My Flights shows the stored fare breakdown; Loyalty and Trips shows the current tier benefits and historical savings. The administrator summary totals all flight loyalty discounts applied.

### Step 3: Configure the Backend

Navigate to the backend folder:

```bash
cd backend
```

Install dependencies:

```bash
npm install
```

Configure your database credentials using the `.env.example` file.

Create your local `.env` file and provide the required configuration.

**Never upload your actual `.env` file or database passwords to GitHub.**

### Step 4: Start the Backend

Run the development command configured in the backend's `package.json`.

### Step 5: Configure the Frontend

Open another terminal:

```bash
cd frontend
```

Install dependencies:

```bash
npm install
```

Start the frontend development server:

```bash
npm run dev
```

Open the local URL displayed in your terminal to access the application.

---

## 🎯 Project Objectives

* Develop a database-driven railway reservation system.
* Implement efficient passenger and train management.
* Automate ticket cancellation and waitlist promotion using SQL triggers.
* Demonstrate stored procedures, constraints, views, and indexing.
* Introduce historical-data-based waitlist confirmation estimation.
* Extend the system with a separate airline booking module that shares only the passenger account and loyalty points.
* Apply database management concepts to a practical real-world problem.

---

## 🔮 Future Scope

The system can be further improved by introducing:

* Real-time train tracking.
* Online payment gateway integration.
* Email and SMS booking notifications.
* More advanced prediction models.
* Improved passenger dashboards.
* Advanced analytics and reservation reports.

---

## 👨‍💻 Contributors

**Developed as a Database Management System (DBMS) academic project.**

Team Members:

* Member 1 – [Name]
* Member 2 – [Name]
* Member 3 – [Name]
* Member 4 – [Name]

Institution: Netaji Subhas University of Technology (NSUT)

---

## 📚 Academic Context

This project was developed to demonstrate the practical implementation of Database Management System concepts, including:

* Relational Database Design
* Entity Relationship Modelling
* SQL Queries
* Database Constraints
* Stored Procedures
* Triggers
* Views
* Indexing
* Transaction Management

---

⭐ If you find this project interesting, feel free to explore the repository!

### Flight loyalty discounts

Run `database/24_air_loyalty_flight_discounts.sql` after the airline schema, shared loyalty setup, and airline procedures are installed. BASIC (<1,000 points) receives 0%, SILVER (1,000-4,999 points) receives 5%, and GOLD (5,000+ points) receives 10% off dynamic flight fares. The discount is calculated in MySQL at booking time and the database stores base fare, tier at booking, percentage, discount amount, and final amount paid.
