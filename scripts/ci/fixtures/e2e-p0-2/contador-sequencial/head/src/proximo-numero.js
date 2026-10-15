'use strict';

function proximoNumero(valor) {
  if (typeof valor !== 'number') {
    throw new TypeError('proximoNumero espera um valor do tipo number');
  }
  if (!Number.isInteger(valor) || valor < 0) {
    throw new TypeError('proximoNumero espera um inteiro maior ou igual a zero');
  }
  return valor + 1;
}

module.exports = { proximoNumero };
