#+ Database creation script for SQLite officestore database
#+
#+ Note: This script is a helper script to create an empty database schema
#+       Adapt it to fit your needs

IMPORT os

PUBLIC FUNCTION create_officestore_database()

    CALL db_drop_tables()
    CALL db_create_tables()
    CALL db_load_data()

END FUNCTION

#+ Create all tables in database.
PRIVATE FUNCTION db_create_tables()
    WHENEVER ERROR STOP

    EXECUTE IMMEDIATE "CREATE TABLE supplier (
        suppid SERIAL NOT NULL,
        name CHAR(80),
        sustatus CHAR(2) NOT NULL,
        addr1 CHAR(80),
        addr2 CHAR(80),
        city CHAR(80),
        state CHAR(80),
        zip CHAR(5),
        phone CHAR(80))"

    EXECUTE IMMEDIATE "CREATE TABLE category (
        catid CHAR(10) NOT NULL,
        catorder SMALLINT,
        catname CHAR(80),
        catdesc CHAR(255),
        catpic CHAR(255),
        CONSTRAINT sqlite_autoindex_category_1 PRIMARY KEY(catid))"

    EXECUTE IMMEDIATE "CREATE TABLE country (
        code CHAR(3) NOT NULL,
        codedesc CHAR(50),
        CONSTRAINT sqlite_autoindex_country_1 PRIMARY KEY(code))"

    EXECUTE IMMEDIATE "CREATE TABLE product (
        productid CHAR(10) NOT NULL,
        catid CHAR(10) NOT NULL,
        prodname CHAR(80),
        proddesc CHAR(255),
        prodpic CHAR(255),
        CONSTRAINT sqlite_autoindex_product_1 PRIMARY KEY(productid),
        CONSTRAINT fk_product_category_0 FOREIGN KEY(catid)
            REFERENCES category(catid))"

    EXECUTE IMMEDIATE "CREATE TABLE account (
        userid CHAR(80) NOT NULL,
        email CHAR(80),
        firstname CHAR(80) NOT NULL,
        lastname CHAR(80) NOT NULL,
        acstatus CHAR(2),
        addr1 CHAR(80),
        addr2 CHAR(40),
        city CHAR(80),
        state CHAR(80),
        zip CHAR(20),
        country CHAR(3),
        phone CHAR(80),
        langpref CHAR(80),
        favcategory CHAR(10),
        mylistopt INTEGER,
        banneropt INTEGER,
        sourceapp CHAR(3),
        CONSTRAINT sqlite_autoindex_account_1 PRIMARY KEY(userid),
        CONSTRAINT fk_account_category_0 FOREIGN KEY(favcategory)
            REFERENCES category(catid),
        CONSTRAINT fk_account_country_1 FOREIGN KEY(country)
            REFERENCES country(code))"

    EXECUTE IMMEDIATE "CREATE TABLE item (
        itemid CHAR(10) NOT NULL,
        productid CHAR(10) NOT NULL,
        listprice DECIMAL(10,2),
        unitcost DECIMAL(10,2),
        supplier INTEGER,
        itstatus CHAR(2),
        attr1 CHAR(80),
        attr2 CHAR(80),
        attr3 CHAR(80),
        attr4 CHAR(80),
        attr5 CHAR(80),
        CONSTRAINT sqlite_autoindex_item_1 PRIMARY KEY(itemid),
        CONSTRAINT fk_item_product_0 FOREIGN KEY(productid)
            REFERENCES product(productid),
        CONSTRAINT fk_item_supplier_1 FOREIGN KEY(supplier)
            REFERENCES supplier(suppid))"

    EXECUTE IMMEDIATE "CREATE TABLE inventory (
        itemid CHAR(10) NOT NULL,
        qty INTEGER NOT NULL,
        CONSTRAINT sqlite_autoindex_inventory_1 PRIMARY KEY(itemid),
        CONSTRAINT fk_inventory_item_0 FOREIGN KEY(itemid)
            REFERENCES item(itemid))"

    EXECUTE IMMEDIATE "CREATE TABLE orders (
        orderid SERIAL NOT NULL,
        userid CHAR(80) NOT NULL,
        orderdate DATE NOT NULL,
        shipfirstname CHAR(80),
        shiplastname CHAR(80),
        shipaddr1 CHAR(80),
        shipaddr2 CHAR(80),
        shipcity CHAR(80),
        shipstate CHAR(80),
        shipzip CHAR(20),
        shipcountry CHAR(3),
        billfirstname CHAR(80),
        billlastname CHAR(80),
        billaddr1 CHAR(80),
        billaddr2 CHAR(80),
        billcity CHAR(80),
        billstate CHAR(80),
        billzip CHAR(20),
        billcountry CHAR(3),
        totalprice DECIMAL(10,2) NOT NULL,
        creditcard CHAR(80),
        exprdate CHAR(7),
        cardtype CHAR(80),
        sourceapp CHAR(3) NOT NULL,
        CONSTRAINT fk_orders_account_0 FOREIGN KEY(userid)
            REFERENCES account(userid),
        CONSTRAINT fk_orders_country_1 FOREIGN KEY(billcountry)
            REFERENCES country(code),
        CONSTRAINT fk_orders_country_2 FOREIGN KEY(shipcountry)
            REFERENCES country(code))"

    EXECUTE IMMEDIATE "CREATE TABLE lineitem (
        orderid INTEGER NOT NULL,
        linenum INTEGER NOT NULL,
        itemid CHAR(10) NOT NULL,
        quantity INTEGER NOT NULL,
        unitprice DECIMAL(10,2) NOT NULL,
        CONSTRAINT sqlite_autoindex_lineitem_1 PRIMARY KEY(orderid, linenum),
        CONSTRAINT fk_lineitem_orders_0 FOREIGN KEY(orderid)
            REFERENCES orders(orderid)
            ON DELETE CASCADE,
        CONSTRAINT fk_lineitem_item_1 FOREIGN KEY(itemid)
            REFERENCES item(itemid))"

    EXECUTE IMMEDIATE "CREATE TABLE orderstatus (
        orderid INTEGER NOT NULL,
        linenum INTEGER NOT NULL,
        mdate DATE NOT NULL,
        orstatus CHAR(2) NOT NULL,
        CONSTRAINT sqlite_autoindex_orderstatus_1 PRIMARY KEY(orderid, linenum),
        CONSTRAINT fk_orderstatus_orders_0 FOREIGN KEY(orderid)
            REFERENCES orders(orderid))"

    EXECUTE IMMEDIATE "CREATE TABLE seqreg (
        sr_name VARCHAR(30) NOT NULL,
        sr_last INTEGER NOT NULL,
        CONSTRAINT sqlite_autoindex_seqreg_1 PRIMARY KEY(sr_name))"

    EXECUTE IMMEDIATE "CREATE TABLE signon (
        userid CHAR(80) NOT NULL,
        password CHAR(25) NOT NULL,
        CONSTRAINT sqlite_autoindex_signon_1 PRIMARY KEY(userid),
        CONSTRAINT fk_signon_account_0 FOREIGN KEY(userid)
            REFERENCES account(userid)
            ON DELETE CASCADE)"

END FUNCTION

#+ Drop all tables from database.
PRIVATE FUNCTION db_drop_tables()

    WHENEVER ERROR CONTINUE

    EXECUTE IMMEDIATE "DROP TABLE signon"
    EXECUTE IMMEDIATE "DROP TABLE seqreg"
    EXECUTE IMMEDIATE "DROP TABLE orderstatus"
    EXECUTE IMMEDIATE "DROP TABLE lineitem"
    EXECUTE IMMEDIATE "DROP TABLE orders"
    EXECUTE IMMEDIATE "DROP TABLE inventory"
    EXECUTE IMMEDIATE "DROP TABLE item"

    EXECUTE IMMEDIATE "DROP TABLE account"
    EXECUTE IMMEDIATE "DROP TABLE product"

    EXECUTE IMMEDIATE "DROP TABLE category"
    EXECUTE IMMEDIATE "DROP TABLE country"
    EXECUTE IMMEDIATE "DROP TABLE supplier"

END FUNCTION

PRIVATE FUNCTION db_load_data()
    DEFINE tableList DYNAMIC ARRAY OF STRING =
        ["supplier",
            "country",
            "category",
            "product",
            "account",
            "item",
            "inventory",
            "orders",
            "lineitem",
            "orderstatus",
            "seqreg",
            "signon"]
    DEFINE idx INTEGER

    FOR idx = 1 TO tableList.getLength()
        CALL db_load_table(tableList[idx])
    END FOR

END FUNCTION #db_load_data

PRIVATE FUNCTION db_load_table(tablename STRING) RETURNS()
    DEFINE sqlText STRING
    DEFINE filename STRING

    LET filename = SFMT("..%1data%1%2.unl", os.Path.separator(), tablename)

    LET sqlText = SFMT("INSERT INTO %1", tablename)
    DISPLAY SFMT("File name: %1 SQL: %2", filename, sqlText)
    LOAD FROM filename sqlText

END FUNCTION #db_load_table
