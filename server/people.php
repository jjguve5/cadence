<?php
// The people who use this server. Only the owner (the token in config.php) can see or change the list.
//   GET                           -> {"people": [{id, name, created}]}
//   POST {"name": "Ana"}          -> {"id", "name", "token", "setup": "cadence://setup?server=...&token=..."}
//                                    the token is shown once; only its hash is kept
//   POST {"remove": "p_..."}      -> takes away that person's access; their folder stays until you delete it
require __DIR__ . '/lib.php';
require_token();
if (!is_owner()) fail(403, 'only the owner manages people');
$file = __DIR__ . '/data/people.php';
$people = people();
$list = fn() => array_values(array_map(fn($p) => ['id' => $p['id'], 'name' => $p['name'], 'created' => $p['created']], people()));
if ($_SERVER['REQUEST_METHOD'] !== 'POST') reply(['people' => $list()]);

$body = json_decode(file_get_contents('php://input', false, null, 0, 10000), true);
if (!is_array($body)) fail(400, 'bad request');
if (isset($body['remove'])) {
	$people = array_filter($people, fn($p) => $p['id'] !== $body['remove']);
	file_put_contents($file, GUARD . json_encode((object) $people), LOCK_EX);
	reply(['people' => $list()]);
}
$name = trim(mb_substr((string) ($body['name'] ?? ''), 0, 40));
if ($name === '') fail(400, 'a name, please');
$token = bin2hex(random_bytes(24));
$id = 'p_' . bin2hex(random_bytes(6));
$people[hash('sha256', $token)] = ['id' => $id, 'name' => $name, 'created' => time()];
if (!is_dir(__DIR__ . '/data')) mkdir(__DIR__ . '/data', 0700, true);
file_put_contents($file, GUARD . json_encode((object) $people, JSON_UNESCAPED_UNICODE), LOCK_EX);
$server = 'https://' . $_SERVER['HTTP_HOST'] . rtrim(dirname($_SERVER['SCRIPT_NAME']), '/');
reply(['id' => $id, 'name' => $name, 'token' => $token, 'setup' => 'cadence://setup?' . http_build_query(['server' => $server, 'token' => $token])]);
