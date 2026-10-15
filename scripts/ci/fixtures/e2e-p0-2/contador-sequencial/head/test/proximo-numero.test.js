'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

test('T-01.01 integracao: src/index.js reexporta proximoNumero de src/proximo-numero.js', () => {
  const lib = require('../src/index.js');
  const modulo = require('../src/proximo-numero.js');
  assert.equal(typeof modulo.proximoNumero, 'function');
  assert.equal(lib.proximoNumero, modulo.proximoNumero);
});

test('T-01.01 funcional: proximoNumero e funcao e o index continua objeto', () => {
  const { proximoNumero } = require('../src/proximo-numero.js');
  assert.equal(typeof proximoNumero, 'function');
  assert.equal(typeof require('../src/index.js'), 'object');
});

test('T-02.01 integracao: proximoNumero(0) pelo objeto exportado de src/index.js devolve 1', () => {
  const { proximoNumero } = require('../src/index.js');
  assert.equal(proximoNumero(0), 1);
});

test('T-02.01 funcional: 41, -0 e MAX_SAFE_INTEGER devolvem 42, 1 e MAX_SAFE_INTEGER + 1', () => {
  const { proximoNumero } = require('../src/proximo-numero.js');
  assert.equal(proximoNumero(41), 42);
  assert.equal(proximoNumero(-0), 1);
  assert.equal(proximoNumero(Number.MAX_SAFE_INTEGER), Number.MAX_SAFE_INTEGER + 1);
  // D-09: acima de MAX_SAFE_INTEGER tambem e aceito; derruba validacao por Number.isSafeInteger
  assert.equal(proximoNumero(2 ** 53), 2 ** 53 + 1);
});

test("T-02.02 integracao: proximoNumero('1') pelo objeto exportado de src/index.js lanca TypeError", () => {
  const { proximoNumero } = require('../src/index.js');
  assert.throws(() => proximoNumero('1'), TypeError);
});

test("T-02.02 funcional: 1n, '1' e new Number(1) lancam TypeError", () => {
  const { proximoNumero } = require('../src/proximo-numero.js');
  // undefined, null e true derrubam validacao por lista de tipos proibidos (1n ja lanca TypeError nativo)
  for (const entrada of [1n, '1', new Number(1), undefined, null, true]) {
    assert.throws(() => proximoNumero(entrada), TypeError);
  }
});

test('T-02.03 integracao: proximoNumero(-1) pelo objeto exportado de src/index.js lanca TypeError', () => {
  const { proximoNumero } = require('../src/index.js');
  assert.throws(() => proximoNumero(-1), TypeError);
});

test('T-02.03 funcional: -1, 1.5, NaN, Infinity e -Infinity lancam TypeError', () => {
  const { proximoNumero } = require('../src/proximo-numero.js');
  for (const entrada of [-1, 1.5, NaN, Infinity, -Infinity]) {
    assert.throws(() => proximoNumero(entrada), TypeError);
  }
});
