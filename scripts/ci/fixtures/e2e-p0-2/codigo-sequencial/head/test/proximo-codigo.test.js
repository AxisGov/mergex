'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const CAMINHO_NUMERO = require.resolve('../src/proximo-numero.js');
const CAMINHO_CODIGO = require.resolve('../src/proximo-codigo.js');

// Carrega src/proximo-codigo.js com um duble de proximoNumero no require.cache
// e apaga as duas entradas ao fim, para os proximos require usarem os modulos reais.
function comDubleDeProximoNumero(duble, usar) {
  delete require.cache[CAMINHO_CODIGO];
  require.cache[CAMINHO_NUMERO] = {
    id: CAMINHO_NUMERO,
    filename: CAMINHO_NUMERO,
    loaded: true,
    exports: { proximoNumero: duble },
  };
  try {
    return usar(require('../src/proximo-codigo.js').proximoCodigo);
  } finally {
    delete require.cache[CAMINHO_CODIGO];
    delete require.cache[CAMINHO_NUMERO];
  }
}

test('FT-02 T-01.01 integracao: src/index.js reexporta proximoCodigo e mantem proximoNumero', () => {
  const lib = require('../src/index.js');
  assert.equal(lib.proximoCodigo, require('../src/proximo-codigo.js').proximoCodigo);
  assert.equal(lib.proximoNumero, require('../src/proximo-numero.js').proximoNumero);
  assert.equal(typeof lib.proximoCodigo, 'function');
});

test('FT-02 T-01.01 funcional: proximoCodigo e funcao e o index continua objeto', () => {
  const { proximoCodigo } = require('../src/proximo-codigo.js');
  assert.equal(typeof proximoCodigo, 'function');
  assert.equal(typeof require('../src/index.js'), 'object');
});

test("FT-02 T-02.01 integracao: '1' e -1 pelo index lancam TypeError com a mesma mensagem de proximoNumero", () => {
  const { proximoCodigo, proximoNumero } = require('../src/index.js');
  for (const entrada of ['1', -1]) {
    let esperado;
    try {
      proximoNumero(entrada);
    } catch (erro) {
      esperado = erro;
    }
    assert.ok(esperado instanceof TypeError);
    assert.throws(() => proximoCodigo(entrada), (erro) => erro instanceof TypeError && erro.message === esperado.message);
  }
});

test("FT-02 T-02.01 funcional: erro sentinela do duble de proximoNumero chega identico e o duble recebe '1'", () => {
  const sentinela = new Error('sentinela');
  const chamadas = [];
  const duble = (valor) => {
    chamadas.push(valor);
    throw sentinela;
  };
  comDubleDeProximoNumero(duble, (proximoCodigo) => {
    assert.throws(() => proximoCodigo('1'), (erro) => erro === sentinela);
  });
  assert.deepEqual(chamadas, ['1']);
  // restauracao: novo require usa o proximoNumero real
  const { proximoCodigo } = require('../src/proximo-codigo.js');
  assert.throws(() => proximoCodigo('1'), (erro) => erro instanceof TypeError && erro !== sentinela);
});

test('FT-02 T-02.02 integracao: proximoCodigo(999999) pelo index devolve SEQ-1000000', () => {
  const { proximoCodigo } = require('../src/index.js');
  assert.equal(proximoCodigo(999999), 'SEQ-1000000');
});

test('FT-02 T-02.02 funcional: com duble de proximoNumero devolvendo 1234567, proximoCodigo(5) devolve SEQ-1234567 e o duble recebe 5 uma vez', () => {
  const chamadas = [];
  const duble = (valor) => {
    chamadas.push(valor);
    return 1234567;
  };
  comDubleDeProximoNumero(duble, (proximoCodigo) => {
    assert.equal(proximoCodigo(5), 'SEQ-1234567');
  });
  assert.deepEqual(chamadas, [5]);
  // restauracao: novo require usa o proximoNumero real
  assert.equal(require('../src/proximo-codigo.js').proximoCodigo(999999), 'SEQ-1000000');
});

test('FT-02 T-02.03 integracao: proximoCodigo(1) pelo index devolve SEQ-000002', () => {
  const { proximoCodigo } = require('../src/index.js');
  assert.equal(proximoCodigo(1), 'SEQ-000002');
});

test('FT-02 T-02.03 funcional: 0, 41, 999999 e 1234567 devolvem SEQ-000001, SEQ-000042, SEQ-1000000 e SEQ-1234568', () => {
  const { proximoCodigo } = require('../src/proximo-codigo.js');
  assert.equal(proximoCodigo(0), 'SEQ-000001');
  assert.equal(proximoCodigo(41), 'SEQ-000042');
  assert.equal(proximoCodigo(999999), 'SEQ-1000000');
  assert.equal(proximoCodigo(1234567), 'SEQ-1234568');
});
