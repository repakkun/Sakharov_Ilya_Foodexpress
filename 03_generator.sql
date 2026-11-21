SET search_path TO sakharov_food, public;

CREATE PROCEDURE insert_test_data(value int) LANGUAGE plpgsql AS $$
DECLARE
 v_clients uuid[] := ARRAY[]::uuid[];
 v_restaurants uuid[] := ARRAY[]::uuid[];
 v_couriers uuid[] := ARRAY[]::uuid[];
 v_categories uuid[] := ARRAY[]::uuid[];
 v_products uuid[] := ARRAY[]::uuid[];
 v_client_addresses uuid[] := ARRAY[]::uuid[];
 v_orders uuid[] := ARRAY[]::uuid[];
 v_order_clients uuid[] := ARRAY[]::uuid[];
 v_order_rests uuid[] := ARRAY[]::uuid[];
 v_id uuid; v_address uuid; v_product uuid; v_order uuid;
 v_client uuid; v_rest uuid; v_courier uuid;
 v_amount numeric(14,2); v_commission numeric(14,2); v_total numeric(14,2);
 v_status order_status; v_payment_status payment_status;
 v_date timestamp; v_month date; v_coeff numeric(3,2);
 v_idx int; v_prev int; v_offset text; v_type review_entity_type;
BEGIN
 IF value IS NULL OR value < 1 THEN RAISE EXCEPTION 'value должен быть положительным'; END IF;
 v_offset:=left(replace(exts.uuid_generate_v4()::text,'-',''),12);
 FOR i IN 1..value LOOP
  INSERT INTO client(login,password,phone_number)
  VALUES ('client_'||v_offset||'_'||i, md5(random()::text),
   ('79'||lpad((floor(random()*1000000000))::bigint::text,9,'0'))::char(11))
  RETURNING client_id INTO v_id;
  v_clients:=array_append(v_clients,v_id);
  INSERT INTO courier(fio,phone_number,status,hire_date,dismissal_date,coefficient)
  VALUES ('Курьер '||i||' '||v_offset,
   ('78'||lpad((floor(random()*1000000000))::bigint::text,9,'0'))::char(11),
   CASE WHEN i=1 THEN 'свободен'::courier_status
    WHEN i % 6 = 0 THEN 'уволен'::courier_status
    ELSE (ARRAY['свободен','занят','на_доставке']::courier_status[])[1+floor(random()*3)::int] END,
   (current_date-interval '6 months')::date,
   CASE WHEN i<>1 AND i%6=0 THEN current_date ELSE NULL END, 0.1)
  RETURNING courier_id INTO v_id;
  v_couriers:=array_append(v_couriers,v_id);
  INSERT INTO product_category(product_category_name)
  VALUES ('Категория '||v_offset||' '||i) RETURNING product_category_id INTO v_id;
  v_categories:=array_append(v_categories,v_id);
  INSERT INTO address(street,house_number,apartment_office)
  VALUES ('Ресторанная '||v_offset||' '||i, i::text, NULL) RETURNING address_id INTO v_address;
  INSERT INTO restaurant(restaurant_name,address_id,description,work_start,work_end,company_details,status)
  VALUES ('Ресторан '||v_offset||' '||i,v_address,'Доставка еды','09:00','23:00',
   'Реквизиты ресторана '||i, (ARRAY['активен','неактивен']::restaurant_status[])[1+(i%2)])
  RETURNING restaurant_id INTO v_id;
  v_restaurants:=array_append(v_restaurants,v_id);
 END LOOP;

 FOR i IN 1..value*4 LOOP
  INSERT INTO address(street,house_number,apartment_office)
  VALUES ('Клиентская '||v_offset||' '||i, (1+i%50)::text,
   CASE WHEN i%4=0 THEN NULL ELSE (i%100+1)::text END)
  RETURNING address_id INTO v_address;
  v_client_addresses:=array_append(v_client_addresses,v_address);
  INSERT INTO client_address(client_id,address_id)
  VALUES (v_clients[1+(i-1)%value],v_address);
 END LOOP;

 FOR i IN 1..value*5 LOOP
  v_rest:=v_restaurants[1+(i-1)%value];
  INSERT INTO product(product_name,product_category_id,price,restaurant_id,photo_url,status,description)
  VALUES ('Блюдо '||v_offset||' '||i,v_categories[1+(i-1)%value],
   1000+(i%20)*30,v_rest,
   CASE WHEN i%5=0 THEN NULL ELSE 'https://example.org/food/'||i END,
   (ARRAY['доступно','нет_в_наличии','архив']::product_status[])[1+(i-1)%3],
   'Описание блюда '||i)
  RETURNING product_id INTO v_id;
  v_products:=array_append(v_products,v_id);
 END LOOP;

 FOR i IN 1..value*5 LOOP
  v_idx:=1+(i-1)%value;
  v_client:=v_clients[v_idx];
  v_rest:=v_restaurants[v_idx];
  v_courier:=v_couriers[v_idx];
  -- Выбираем адрес, принадлежащий клиенту.
  v_address:=v_client_addresses[(v_idx-1)+value*(floor((i-1)::numeric/value)::int%4)+1];
  -- Блюдо принадлежит ресторану заказа.
  v_product:=v_products[i];
  v_amount:=1000+(i%20)*30;
  v_commission:=round(v_amount*0.1,2);
  v_total:=v_amount+v_commission;
  v_date:=localtimestamp - (random()*interval '170 days');
  v_status:=CASE WHEN i%5=0 THEN 'отменён'::order_status
   WHEN i%5=1 THEN 'создан'::order_status
   WHEN i%5=2 THEN 'готовится'::order_status
   WHEN i%5=3 THEN 'в_доставке'::order_status
   ELSE 'доставлен'::order_status END;
  INSERT INTO "order"(courier_id,client_id,address_id,restaurant_id,order_timestamp,
   delivery_timestamp,order_amount,commission,total_amount,status,pay_status,description)
  VALUES(v_courier,v_client,v_address,v_rest,v_date,
   CASE WHEN v_status='доставлен' THEN v_date+interval '50 minutes' ELSE NULL END,
   v_amount,v_commission,v_total,v_status,'ожидает','Заказ '||i)
  RETURNING order_id INTO v_order;
  v_orders:=array_append(v_orders,v_order);
  v_order_clients:=array_append(v_order_clients,v_client);
  v_order_rests:=array_append(v_order_rests,v_rest);
  INSERT INTO order_structure(order_id,product_id,quantity) VALUES(v_order,v_product,1);
  v_payment_status:=(ARRAY['успех','ошибка','в_обработке']::payment_status[])[1+(i-1)%3];
  INSERT INTO payment(order_id,payment_type,amount,transaction_id,transaction_timestamp,status)
  VALUES(v_order,(ARRAY['карта','наличные','безнал']::payment_type[])[1+(i-1)%3],
   v_total,'tr_'||v_offset||'_'||i,v_date,v_payment_status);
 END LOOP;

 FOR i IN 1..value*5 LOOP
  v_idx:=1+(i-1)%array_length(v_orders,1);
  v_order:=v_orders[v_idx];
  v_client:=v_order_clients[v_idx];
  v_rest:=v_order_rests[v_idx];
  v_type:=(ARRAY['блюдо','ресторан','заказ']::review_entity_type[])[1+(i-1)%3];
  v_id:=CASE WHEN v_type='блюдо' THEN v_products[v_idx]
       WHEN v_type='ресторан' THEN v_rest ELSE v_order END;
  SELECT order_timestamp+interval '2 hours' INTO v_date FROM "order" WHERE order_id=v_order;
  INSERT INTO review(client_id,review_timestamp,entity_id,entity_type,order_id,
   description,photo_url,rating)
  VALUES(v_client,v_date,v_id,v_type,v_order,'Отзыв '||i,
   CASE WHEN i%4=0 THEN NULL ELSE 'https://example.org/review/'||i END,1+(i%5));
 END LOOP;

 -- Заполняем зарплаты курьеров за шесть месяцев.
 FOR i IN 1..value LOOP
  v_coeff:=0.1;
  FOR m IN REVERSE 5..0 LOOP
   v_month:=(date_trunc('month',current_date)-make_interval(months=>m))::date;
   INSERT INTO courier_pay(year,month,courier_id,amount,coefficient_used)
   SELECT extract(year from v_month)::int,extract(month from v_month)::int,
    v_couriers[i], round(v_coeff*coalesce(sum(o.commission),0),2),v_coeff
   FROM "order" o WHERE o.courier_id=v_couriers[i] AND o.status='доставлен'
    AND o.delivery_timestamp>=v_month AND o.delivery_timestamp<v_month+interval '1 month';
   SELECT count(*) INTO v_prev FROM "order" o
   WHERE o.courier_id=v_couriers[i] AND o.status='доставлен'
    AND o.delivery_timestamp>=v_month AND o.delivery_timestamp<v_month+interval '1 month';
   v_coeff:=CASE WHEN v_prev<=150 THEN 0.1 WHEN v_prev<=250 THEN 0.2
    WHEN v_prev<=500 THEN 0.3 ELSE 0.5 END;
  END LOOP;
  UPDATE courier SET coefficient=v_coeff WHERE courier_id=v_couriers[i] AND status<>'уволен';
 END LOOP;
END $$;
