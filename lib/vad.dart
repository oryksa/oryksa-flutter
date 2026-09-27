import 'dart:math' as math;
import 'dart:typed_data';

/// Decide QUANDO o dono começou e acabou de falar.
///
/// Está aqui fora, separada do ecrã, para poder ser testada com som a sério
/// (ver `test/vad_test.dart`). A voz é o coração do negócio e já se perdeu
/// tempo de mais a adivinhar porque é que ela não respondia.
class Vad {
  Vad({this.sampleRate = 16000});

  final int sampleRate;

  /// Silêncio que fecha a frase.
  ///
  /// A 450 ms cortava a meio e mandava clipes de 100 ms que o Whisper não
  /// conseguia transcrever. Subiu para 900 e passou a funcionar, mas 900 ms é
  /// muita espera numa conversa falada, e o dono queixou-se da lentidão.
  /// Está agora em 700, com `test/silencio_test.dart` a provar com fala a
  /// sério (incluindo pausas entre palavras) que a frase não se parte.
  /// ⚠️ Quem quiser baixar mais: corra esse teste com gravações novas.
  static const quietToCloseMs = 700;

  /// Fala mínima para valer a pena enviar. Abaixo disto é ruído, uma tosse,
  /// uma porta.
  static const minSpeechMs = 500;

  /// Som mínimo gravado (em segundos) para o servidor ter o que ouvir.
  static const minAudioMs = 700;

  /// Corta sozinha ao fim deste tempo, mesmo que a pessoa continue.
  static const maxSpeechMs = 15000;

  /// Quanto tempo de VOZ é preciso, por cima dela, para a calar.
  ///
  /// Duas fatias com tom, cerca de 130 ms. Pode parecer pouco, e seria se o
  /// tempo fosse a única prova. Não é: quem impede o teclado de a calar é o
  /// TOM, e uma tecla não passa nessa prova nem uma vez. Por isso o tempo pode
  /// ser curto, e tem de ser: numa palavra como "Para" quase tudo é o "p", e
  /// só umas fatias têm voz. Começou em 250 ms (um pássaro calava-a), passou
  /// por 700 (ela deixou de obedecer a quem lhe mandava calar) e assentou aqui,
  /// depois de a prova do tom passar a fazer o trabalho pesado.
  static const bargeMs = 130;

  /// Pausa que chega para desistir da interrupção a meio. Sem isto, qualquer
  /// micro-pausa entre sílabas apagava a conta e o dono tinha de gritar uma
  /// frase seguida para a calar.
  ///
  /// Baixou de 220 para 130 ms por causa das TECLAS: a escrever num teclado
  /// batem-se umas cinco teclas por segundo, ou seja uma a cada 200 ms, e com
  /// 220 ms de tolerância isso somava como se fosse uma frase.
  static const bargeGapMs = 130;

  /// Som seguido, sem uma única falha, para não valer uma fatia solta.
  /// O trabalho pesado é todo do tom.
  static const bargeRunMs = 64;

  /// Quão periódico tem de ser para contar como voz. Abaixo disto é barulho:
  /// teclas, palmas, portas, cliques.
  ///
  /// Medido com gravações a sério (`test/voz_vs_ruido_test.dart`):
  /// - teclado: tom entre 0,14 e **0,20**, nunca mais do que isso;
  /// - voz humana: 0,50 a 0,93.
  /// O corte fica a 0,35: bem acima de qualquer tecla e bem abaixo da voz.
  /// É esta prova que garante a regra do dono: só a voz dele a cala.
  static const bargeVozMin = 0.35;

  /// Maior bocado de som SEGUIDO dentro da tentativa de interrupção.
  int _corrida = 0;
  int _maiorCorrida = 0;

  /// Há quanto tempo se provou que aquilo era voz.
  ///
  /// Uma palavra não deixa de ser voz a meio: em "Para", o "p" é um estalo, a
  /// vogal tem tom claro, e o que vem a seguir ainda é a mesma pessoa, embora
  /// a medição do tom já enfraqueça. Depois de provada a voz, o resto da
  /// palavra conta sem ter de a provar outra vez.
  ///
  /// O teclado nunca abre esta janela, porque nunca prova voz nem uma vez.
  int _vozHaMs = 99999;

  /// Quanto tempo dura essa confiança depois da última fatia com tom.
  static const vozValeMs = 300;

  // ⚠️ NÃO existe caminho para som sem tom.
  //
  // Houve aqui um, para apanhar "shhh" e "psst": som alto e seguido meio
  // segundo, sem precisar de tom. Parecia inofensivo e não era: **um avião a
  // passar calou-a**, porque um motor também é alto e seguido. O dono foi
  // claro: "ela tem de conversar, só ser interrompida se for voz; não tap de
  // teclado, não ruído de sala".
  //
  // Por isso a regra passou a ser uma só: SÓ VOZ INTERROMPE. O preço é que um
  // "shhh" sussurrado já não a cala; uma palavra qualquer cala. É o preço
  // certo: um "shhh" falhado repete-se, um avião não se pode evitar.

  /// Os níveis do que se ouviu na tentativa de interrupção, para se poder VER
  /// o que o microfone recebeu em vez de adivinhar. Fica nos registos.
  final List<double> perfil = [];

  /// O que se ouviu na frase que acabou de ser gravada: o pico e o tom.
  /// Servem para saber se ele SUSSURROU e para o relatório de qualidade.
  double picoDaFrase = 0;
  double tomDaFrase = 0;

  /// Isto foi um sussurro?
  ///
  /// Um sussurro é voz sem as cordas vocais: sai baixo e quase sem tom. O dono
  /// quer que ela perceba e que lhe responda também a sussurrar, como a Alexa.
  /// Contrato do ecossistema: pico abaixo de 0,09 e tom abaixo de 0,45.
  bool get foiSussurro => picoDaFrase > 0 && picoDaFrase < 0.09 && tomDaFrase < 0.45;

  /// O som mais alto que entrou enquanto ela falava. Serve para saber, com
  /// números, se quem tentou interromper chegou sequer ao chão exigido.
  double maxEnquantoFala = 0;

  /// O tom mais alto medido na tentativa de interrupção. É o número que diz se
  /// aquilo foi voz ou um barulho, e é o que se quer ver nos registos.
  double tomDaInterrupcao = 0;

  /// Som mínimo para sequer contar como interrupção. É ALTO de propósito: quem
  /// interrompe está a falar para o telemóvel, à distância da mão. Um pássaro
  /// na rua, a televisão na sala ou a voz dela a sair do altifalante ficam
  /// abaixo disto.
  ///
  /// ⚠️ MEDIDO AO VIVO, não escolhido a olho.
  ///
  /// A voz dela a sair do altifalante e a voltar pelo microfone entra a
  /// **0,05**, e tem tom 0,86 (é voz, é mesmo a voz dela). Com o chão a 0,040
  /// ela ouvia-se a si própria e calava-se sozinha a meio da frase, sem
  /// ninguém fazer barulho nenhum. A voz de quem fala ao pé do telemóvel entra
  /// a **0,12 a 0,25**.
  ///
  /// 0,09 fica no meio: o dobro do eco dela, metade da voz de quem fala.
  ///
  /// Tentei em vez disto aprender o eco enquanto ela fala. Não serve: a
  /// aprendizagem apanha também a voz de quem interrompe e levanta a fasquia
  /// até ele nunca mais conseguir calá-la. Um número medido e fixo é mais
  /// honesto do que uma adaptação que se vira contra o dono.
  static const bargeFloor = 0.090;

  /// O mais alto que a fasquia de OUVIR pode chegar, por muito barulho que
  /// haja. Sem isto ela ficava surda num café.
  static const tetoOuvir = 0.10;

  /// Nível máximo que pode ser tomado por "silêncio da sala". Se quem fala já
  /// estava a falar quando isto arrancou, a voz dele NÃO pode passar a ser o
  /// silêncio de referência: ficaria um limiar altíssimo e a app surda.
  static const maxBase = 0.015;

  double base = 0;
  int frames = 0;

  int speechMs = 0;
  int quietMs = 0;
  bool capturing = false;

  /// Nível médio, mínimo e máximo do que está a ser gravado. Serve para
  /// distinguir VOZ de barulho de fundo: a voz sobe e desce muito (vogais
  /// fortes, pausas entre palavras), uma ventoinha ou um motor ficam sempre
  /// no mesmo sítio.
  double _sum = 0;
  double _min = 1;
  double _max = 0;
  int _n = 0;

  /// Tempo a gravar sem uma pausa que chega para desconfiar que é barulho.
  static const noiseAfterMs = 4000;

  /// Voz sobe e desce muito mais do que isto entre pedaços; barulho de fundo não.
  static const flatRatio = 2.5;

  /// Teto do silêncio de referência. Acima disto o limiar ficaria mais alto do
  /// que a voz humana consegue chegar e a app ficava surda para sempre. Quando
  /// o barulho passa daqui, o problema é o sítio (ou o microfone), e quem tem
  /// de saber é a pessoa, não é para se esconder.
  static const maxNoiseBase = 0.12;

  /// Barulho de fundo, não voz: sobe o silêncio de referência para esse nível
  /// e deita fora o que gravou.
  VadStep _noise() {
    final nivel = _n > 0 ? _sum / _n : base;
    base = math.min(math.max(base, nivel), maxNoiseBase);
    return VadStep.done(spokeMs: speechMs, enough: false, isNoise: true, level: nivel);
  }

  /// Isto é uma VOZ humana, ou é um barulho?
  ///
  /// A voz é periódica: as cordas vocais vibram entre uns 70 e 350 vezes por
  /// segundo, e essa repetição vê-se no som. Uma tecla, uma palma, uma porta,
  /// um clique são estalos sem repetição nenhuma. Um pássaro também repete,
  /// mas lá em cima, nos milhares de hertz, fora do alcance de uma pessoa.
  ///
  /// Mede-se por autocorrelação: compara-se o som consigo próprio deslocado no
  /// tempo. Se houver um deslocamento em que ele "encaixa" quase na perfeição,
  /// é periódico, é voz. Não precisa de modelo nenhum nem de pesar na app.
  ///
  /// Existe porque o dono estava a ouvi-la, escrevia no computador, e o
  /// tap-tap-tap das teclas calava-a. Palavras dele: "imagina, a pessoa no
  /// telefone com alguém, ela a falar, a pessoa digita e ela para porque ouviu
  /// a digitação. Não pode."
  static double periodicidade(Uint8List chunk) {
    final n = chunk.lengthInBytes ~/ 2;
    if (n < 512) return 0;
    final d = chunk.buffer.asByteData(chunk.offsetInBytes, n * 2);

    // Um em cada dois valores: chega para o tom da voz e custa metade.
    final m = n ~/ 2;
    final x = Float64List(m);
    var media = 0.0;
    for (var i = 0; i < m; i++) {
      x[i] = d.getInt16(i * 4, Endian.little) / 32768.0;
      media += x[i];
    }
    media /= m;
    var energia = 0.0;
    for (var i = 0; i < m; i++) {
      x[i] -= media;
      energia += x[i] * x[i];
    }
    if (energia <= 0) return 0;

    // A 8000 amostras por segundo (metade de 16000): 70 Hz = 114, 350 Hz = 23.
    const lagMin = 23;
    const lagMax = 114;
    var melhor = 0.0;
    for (var lag = lagMin; lag <= lagMax && lag < m; lag++) {
      var soma = 0.0;
      for (var i = 0; i + lag < m; i++) {
        soma += x[i] * x[i + lag];
      }
      final r = soma / energia;
      if (r > melhor) melhor = r;
    }
    return melhor;
  }

  /// Nível do som deste pedaço (0 a 1).
  static double rmsOf(Uint8List chunk) {
    final n = chunk.lengthInBytes ~/ 2;
    if (n == 0) return 0;
    final d = chunk.buffer.asByteData(chunk.offsetInBytes, n * 2);
    var sum = 0.0;
    for (var k = 0; k < n; k++) {
      final v = d.getInt16(k * 2, Endian.little) / 32768.0;
      sum += v * v;
    }
    return math.sqrt(sum / n);
  }

  /// Recomeçar de zero, incluindo esquecer o silêncio aprendido. Só no arranque
  /// de uma sessão de voz: a seguir a cada frase usa-se [newTurn].
  void reset() {
    base = 0;
    frames = 0;
    newTurn();
  }

  /// Pronta para a frase seguinte, MANTENDO o silêncio já aprendido.
  ///
  /// Reaprender o silêncio depois de cada resposta era o que a deixava surda:
  /// ou perdia os primeiros instantes da frase nova, ou pior, calibrava-se com
  /// a voz de quem já estava a falar. A sala não muda entre frases.
  void newTurn() {
    _corrida = 0;
    _maiorCorrida = 0;
    _vozHaMs = 99999;
    picoDaFrase = 0;
    tomDaFrase = 0;
    tomDaInterrupcao = 0;
    maxEnquantoFala = 0;
    perfil.clear();
    speechMs = 0;
    quietMs = 0;
    capturing = false;
    _sum = 0;
    _min = 1;
    _max = 0;
    _n = 0;
  }

  /// Dá um pedaço de som. Devolve o que fazer a seguir.
  VadStep feed(Uint8List chunk, {bool speaking = false}) {
    final n = chunk.lengthInBytes ~/ 2;
    if (n == 0) return const VadStep.idle();
    final rms = rmsOf(chunk);
    final ms = (n * 1000) ~/ sampleRate;
    frames++;

    // Primeiros pedaços: aprender o silêncio deste sítio, sem nunca passar de
    // [maxBase], e sem deitar fora o som (se já estava a falar, conta).
    if (frames <= 3 && !speaking) {
      base = base == 0 ? math.min(rms, maxBase) : math.min(base, rms);
    }
    // ⚠️ AS DUAS FASQUIAS, e são diferentes de propósito.
    //
    // A CORTAR (ela a falar): manda o chão medido, não o ruído da sala. Estava
    // a multiplicar o ruído por 8, e numa sala com fundo 0,036 a fasquia ia a
    // 0,29: nem uma voz a 0,16 a calava, apesar de o chão dizer 0,09. Duas
    // vezes o ruído chega para acompanhar uma sala barulhenta.
    //
    // A OUVIR (ela calada): acompanha o ruído, mas COM TETO. Sem teto, num
    // café a fasquia chegava a 0,38 e o dono tinha de gritar. A voz de quem
    // fala ao pé do telemóvel dá 0,12 a 0,25; o teto fica em 0,10.
    final speakThr = speaking
        ? math.max(base * 2.0, bargeFloor)
        : math.min(math.max(base * 3.2, 0.014), tetoOuvir);
    final quietThr = math.max(base * 1.8, 0.008);

    // O ruído da sala acompanha-se: desce depressa (ficou tudo calado) e sobe
    // devagar (ligaram o ar condicionado, entraram no carro). Nunca aprende
    // com som alto o bastante para ser voz, senão passava a ignorar-te.
    if (!capturing && !speaking) {
      if (rms < base) {
        base = base * 0.8 + rms * 0.2;
      } else if (rms < speakThr) {
        base = base * 0.98 + rms * 0.02;
      }
    }

    if (speaking) {
      final thr = speakThr;
      if (perfil.length < 40) perfil.add(rms);
      // Só conta como interrupção o que for VOZ. Um estalo de tecla é alto,
      // mas não tem tom nenhum.
      final alto = rms > thr;
      if (rms > maxEnquantoFala) maxEnquantoFala = rms;
      final tom = alto ? periodicidade(chunk) : 0.0;
      if (tom > tomDaInterrupcao) tomDaInterrupcao = tom;
      if (tom >= bargeVozMin) {
        _vozHaMs = 0;
      } else {
        _vozHaMs += ms;
      }
      final ehVoz = alto && _vozHaMs <= vozValeMs;
      if (ehVoz) {
        speechMs += ms;
        quietMs = 0;
        _corrida += ms;
        if (_corrida > _maiorCorrida) _maiorCorrida = _corrida;
        // Tempo que chegue E um bocado seguido que só a voz consegue fazer.
        if (speechMs >= bargeMs && _maiorCorrida >= bargeRunMs) return const VadStep.bargeIn();
      } else {
        _corrida = 0;
        // Uma pausa curta não apaga a conta: entre sílabas há silêncio. Só uma
        // pausa a sério é que diz que aquilo foi um barulho e não alguém a
        // falar connosco.
        quietMs += ms;
        if (quietMs > bargeGapMs) {
          speechMs = 0;
          quietMs = 0;
          _maiorCorrida = 0;
        }
      }
      return const VadStep.idle();
    }

    if (rms > speakThr) {
      capturing = true;
      speechMs += ms;
      quietMs = 0;
      if (rms > picoDaFrase) picoDaFrase = rms;
      final tf = periodicidade(chunk);
      if (tf > tomDaFrase) tomDaFrase = tf;
    } else if (capturing) {
      if (rms < quietThr) quietMs += ms;
    }
    if (capturing) {
      _sum += rms;
      if (rms < _min) _min = rms;
      if (rms > _max) _max = rms;
      _n++;
    }

    if (!capturing) return const VadStep.idle();

    // Barulho de fundo apanhado cedo: alguns segundos sem uma única pausa E
    // sempre ao mesmo nível. Ninguém fala assim; uma ventoinha faz exatamente
    // isto. Não se espera pelos 15 segundos para perceber.
    final plano = _min > 0 && _max < _min * flatRatio;
    if (speechMs > noiseAfterMs && quietMs == 0 && plano) return _noise();

    if (quietMs <= quietToCloseMs && speechMs <= maxSpeechMs) return const VadStep.capturing();

    final spoke = speechMs;
    final nivel = _n > 0 ? _sum / _n : 0.0;

    // Quinze segundos sem UMA pausa não é ninguém a falar: é ruído constante
    // (uma ventoinha, o motor do carro, uma sala cheia). Ninguém fala assim.
    // Sobe-se o silêncio de referência para esse nível e deixa de se confundir.
    if (spoke > maxSpeechMs && quietMs < 200) return _noise();

    // Fim de frase. Só vale a pena enviar se houver mesmo fala.
    return VadStep.done(spokeMs: spoke, enough: spoke >= minSpeechMs, level: nivel);
  }
}

/// O que o ecrã deve fazer com o pedaço que acabou de chegar.
class VadStep {
  final bool isCapturing;
  final bool isDone;
  final bool isBargeIn;
  final int spokeMs;

  /// Não era voz, era barulho de fundo sem fim. O silêncio de referência subiu.
  final bool isNoise;

  /// Nível médio do que se gravou (para os registos de diagnóstico).
  final double level;

  /// Falou o suficiente para valer a pena enviar?
  final bool enough;

  const VadStep.idle()
    : isCapturing = false,
      isDone = false,
      isBargeIn = false,
      spokeMs = 0,
      enough = false,
      isNoise = false,
      level = 0;
  const VadStep.capturing()
    : isCapturing = true,
      isDone = false,
      isBargeIn = false,
      spokeMs = 0,
      enough = false,
      isNoise = false,
      level = 0;
  const VadStep.bargeIn()
    : isCapturing = false,
      isDone = false,
      isBargeIn = true,
      spokeMs = 0,
      enough = false,
      isNoise = false,
      level = 0;
  const VadStep.done({required this.spokeMs, required this.enough, this.isNoise = false, this.level = 0})
    : isCapturing = false,
      isDone = true,
      isBargeIn = false;
}
