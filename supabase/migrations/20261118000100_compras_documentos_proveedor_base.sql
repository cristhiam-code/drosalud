create table if not exists public.documentos_proveedor (
  id uuid primary key default gen_random_uuid(),
  proveedor_id uuid not null references public.proveedores(id),
  tipo_documento text not null check (tipo_documento in ('factura','remision','nota_credito','otro')),
  numero_documento text not null,
  fecha_emision date,
  moneda text not null default 'COP' check (moneda = 'COP'),
  subtotal numeric(14,2) check (subtotal is null or subtotal >= 0),
  descuentos numeric(14,2) not null default 0 check (descuentos >= 0),
  impuestos numeric(14,2) not null default 0 check (impuestos >= 0),
  flete numeric(14,2) not null default 0 check (flete >= 0),
  total numeric(14,2) check (total is null or total >= 0),
  estado text not null default 'registrado' check (estado in ('registrado','parcial','conciliado','con_diferencias','anulado')),
  notas text,
  creado_por uuid not null default auth.uid(),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint documentos_proveedor_numero_unico unique (proveedor_id,tipo_documento,numero_documento)
);

create table if not exists public.documentos_proveedor_ordenes (
  id uuid primary key default gen_random_uuid(),
  documento_id uuid not null references public.documentos_proveedor(id) on delete restrict,
  orden_id uuid not null references public.ordenes_compra(id) on delete restrict,
  creado_en timestamptz not null default now(),
  constraint documentos_proveedor_ordenes_unico unique (documento_id,orden_id)
);

create table if not exists public.documentos_proveedor_items (
  id uuid primary key default gen_random_uuid(),
  documento_id uuid not null references public.documentos_proveedor(id) on delete restrict,
  orden_item_id uuid references public.ordenes_compra_items(id) on delete restrict,
  producto_id uuid not null references public.productos(id) on delete restrict,
  descripcion_documento text,
  presentacion_documento text,
  unidades_por_presentacion integer not null check (unidades_por_presentacion > 0),
  cantidad_documentada integer not null check (cantidad_documentada > 0),
  unidades_documentadas integer generated always as (cantidad_documentada * unidades_por_presentacion) stored,
  precio_por_presentacion numeric(14,2) not null check (precio_por_presentacion >= 0),
  costo_unitario_base numeric(14,4) generated always as (precio_por_presentacion / unidades_por_presentacion) stored,
  creado_en timestamptz not null default now()
);

alter table public.recepciones_compra
  add column if not exists documento_id uuid references public.documentos_proveedor(id) on delete restrict;

create index if not exists idx_documentos_proveedor_fecha on public.documentos_proveedor(fecha_emision desc);
create index if not exists idx_documentos_proveedor_ordenes_orden on public.documentos_proveedor_ordenes(orden_id);
create index if not exists idx_documentos_proveedor_items_documento on public.documentos_proveedor_items(documento_id);
create index if not exists idx_documentos_proveedor_items_orden_item on public.documentos_proveedor_items(orden_item_id);
create index if not exists idx_recepciones_compra_documento on public.recepciones_compra(documento_id);

alter table public.documentos_proveedor enable row level security;
alter table public.documentos_proveedor_ordenes enable row level security;
alter table public.documentos_proveedor_items enable row level security;

create policy documentos_proveedor_select_equipo on public.documentos_proveedor
  for select to authenticated using (public.es_usuario_drosalud());
create policy documentos_proveedor_ordenes_select_equipo on public.documentos_proveedor_ordenes
  for select to authenticated using (public.es_usuario_drosalud());
create policy documentos_proveedor_items_select_equipo on public.documentos_proveedor_items
  for select to authenticated using (public.es_usuario_drosalud());

revoke insert, update, delete, truncate, references, trigger on public.documentos_proveedor from anon, authenticated;
revoke insert, update, delete, truncate, references, trigger on public.documentos_proveedor_ordenes from anon, authenticated;
revoke insert, update, delete, truncate, references, trigger on public.documentos_proveedor_items from anon, authenticated;

grant select on public.documentos_proveedor to authenticated;
grant select on public.documentos_proveedor_ordenes to authenticated;
grant select on public.documentos_proveedor_items to authenticated;

comment on table public.documentos_proveedor is 'Documentos comerciales del proveedor; independientes de la recepción física.';
comment on table public.documentos_proveedor_ordenes is 'Relación N:M entre documentos de proveedor y órdenes de compra.';
comment on table public.documentos_proveedor_items is 'Líneas documentadas; cantidades y costos conservan la presentación declarada en el documento.';
