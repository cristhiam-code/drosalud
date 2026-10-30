-- Drosalud: rentabilidad de domicilios
-- Cambio aditivo: conserva los recibos históricos; NULL se interpreta como 0.
ALTER TABLE public.recibos
ADD COLUMN IF NOT EXISTS costo_mensajero numeric(14,2) NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.recibos.costo_mensajero IS
'Pago real a un mensajero externo. Cero cuando la entrega la realiza el propietario.';
