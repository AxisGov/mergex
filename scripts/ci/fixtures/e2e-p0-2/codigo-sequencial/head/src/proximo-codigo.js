'use strict';

const { proximoNumero } = require('./proximo-numero.js');

function proximoCodigo(valor) {
  return 'SEQ-' + String(proximoNumero(valor)).padStart(6, '0');
}

module.exports = { proximoCodigo };
