#+ Database creation script for SQLite
#+
#+ Note: This script is a helper script to create an empty database schema
#+       Adapt it to fit your needs

IMPORT os

PRIVATE CONSTANT c_prefix = "custdemo_"

PUBLIC FUNCTION create_custdemo_database()

    CALL db_drop_tables()
    CALL db_create_tables()
    CALL db_load_data()

END FUNCTION

#+ Create all tables in database.
PRIVATE FUNCTION db_create_tables()
    WHENEVER ERROR STOP

    EXECUTE IMMEDIATE "CREATE TABLE empty_table (
        empty_col CHAR(1)
        )"

    EXECUTE IMMEDIATE "CREATE TABLE state (
        state_code CHAR(2) NOT NULL,
        state_name CHAR(15),
        CONSTRAINT sqlite_autoindex_state_1 PRIMARY KEY(state_code))"

    EXECUTE IMMEDIATE "CREATE TABLE factory (
        fac_code CHAR(3) NOT NULL,
        fac_name CHAR(15),
        CONSTRAINT sqlite_autoindex_factory_1 PRIMARY KEY(fac_code))"

    EXECUTE IMMEDIATE "CREATE TABLE customer (
        store_num INTEGER NOT NULL,
        store_name CHAR(30),
        addr CHAR(20),
        addr2 CHAR(20),
        city CHAR(15),
        state CHAR(2),
        zipcode CHAR(5),
        contact_name CHAR(30),
        phone CHAR(18),
        CONSTRAINT primary_key_customer PRIMARY KEY(store_num),
        CONSTRAINT fk_customer_state_0 FOREIGN KEY(state)
            REFERENCES state(state_code))"

    EXECUTE IMMEDIATE "CREATE TABLE stock (
        stock_num INTEGER NOT NULL,
        fac_code CHAR(3) NOT NULL,
        description CHAR(15),
        reg_price DECIMAL(8,2),
        promo_price DECIMAL(8,2),
        price_updated DATE,
        unit CHAR(4),
        CONSTRAINT primary_key_stock PRIMARY KEY(stock_num),
        CONSTRAINT fk_stock_factory_0 FOREIGN KEY(fac_code)
            REFERENCES factory(fac_code))"

    EXECUTE IMMEDIATE "CREATE TABLE orders (
        order_num INTEGER NOT NULL,
        order_date DATE,
        store_num INTEGER NOT NULL,
        fac_code CHAR(3),
        ship_instr CHAR(10),
        promo CHAR(1),
        CONSTRAINT primary_key_orders PRIMARY KEY(order_num),
        CONSTRAINT fk_orders_customer_0 FOREIGN KEY(store_num)
            REFERENCES customer(store_num),
        CONSTRAINT fk_orders_factory_1 FOREIGN KEY(fac_code)
            REFERENCES factory(fac_code))"

    EXECUTE IMMEDIATE "CREATE TABLE items (
        order_num INTEGER NOT NULL,
        stock_num INTEGER NOT NULL,
        quantity SMALLINT,
        price DECIMAL(8,2),
        CONSTRAINT sqlite_autoindex_items_1 PRIMARY KEY(order_num, stock_num),
        CONSTRAINT fk_items_stock_0 FOREIGN KEY(stock_num)
            REFERENCES stock(stock_num),
        CONSTRAINT fk_items_orders_1 FOREIGN KEY(order_num)
            REFERENCES orders(order_num))"

END FUNCTION

#+ Drop all tables from database.
PRIVATE FUNCTION db_drop_tables()

    WHENEVER ERROR CONTINUE

    EXECUTE IMMEDIATE "DROP TABLE empty_table"
    EXECUTE IMMEDIATE "DROP TABLE items"
    EXECUTE IMMEDIATE "DROP TABLE orders"
    EXECUTE IMMEDIATE "DROP TABLE stock"
    EXECUTE IMMEDIATE "DROP TABLE customer"
    EXECUTE IMMEDIATE "DROP TABLE factory"
    EXECUTE IMMEDIATE "DROP TABLE state"

END FUNCTION #db_drop_tables

PRIVATE FUNCTION db_load_data()
    DEFINE tableList DYNAMIC ARRAY OF STRING =
        ["empty_table",
            "state",
            "factory",
            "customer",
            "stock",
            "orders",
            "items"]
    DEFINE idx INTEGER

    FOR idx = 1 TO tableList.getLength()
        CALL db_load_table(tableList[idx])
    END FOR

END FUNCTION #db_load_data

PRIVATE FUNCTION db_load_table(tablename STRING) RETURNS()
    DEFINE sqlText STRING
    DEFINE filename STRING

    LET filename =
        SFMT("..%1data%1%2%3.unl", os.Path.separator(), c_prefix, tablename)

    LET sqlText = SFMT("INSERT INTO %1", tablename)
    DISPLAY SFMT("File name: %1 SQL: %2", filename, sqlText)
    LOAD FROM filename sqlText

END FUNCTION #db_load_table
