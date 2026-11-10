package com.soy.josec.bella_durmiente

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ArranqueReceiverTest {
    private val ahora = 1_000_000L

    @Test
    fun omiteRecordatorioHeredado() =
        assertFalse(ArranqueReceiver.debeReprogramar(10001, ahora + 1, ahora))

    @Test
    fun omiteFechaPasada() =
        assertFalse(ArranqueReceiver.debeReprogramar(5, ahora, ahora))

    @Test
    fun reprogramaAlarmaValida() =
        assertTrue(ArranqueReceiver.debeReprogramar(5, ahora + 1, ahora))
}
